import re
import math
from dataclasses import dataclass
from typing import List, Dict, Any, Tuple, Optional

import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
from sentence_transformers import SentenceTransformer, util


# ----------------------------
# Configuration
# ----------------------------
NLI_MODEL_NAME = "roberta-large-mnli"
EMBED_MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

LABEL_MAP = {0: "CONTRADICTION", 1: "NEUTRAL", 2: "ENTAILMENT"}  # roberta-mnli default


# ----------------------------
# Helpers: text cleanup & extraction
# ----------------------------
STOPWORDS = {
    "a","an","the","and","or","but","if","then","else","when","while","to","of","in","on","at","by","for","from",
    "with","without","as","is","are","was","were","be","been","being","it","this","that","these","those","they",
    "their","them","he","she","his","her","you","your","we","our","i","me","my","us","not","no","yes",
    "into","over","under","after","before","between","during","about","above","below"
}

def normalize_spaces(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").strip())

def split_sentences(text: str) -> List[str]:
    text = normalize_spaces(text)
    if not text:
        return []
    parts = re.split(r"(?<=[.!?])\s+|\n+", text)
    return [p.strip(" •-–—\t") for p in parts if p.strip()]

def extract_keywords(text: str, max_words: int = 12) -> List[str]:
    text = normalize_spaces(text)
    words = re.findall(r"[A-Za-z0-9][A-Za-z0-9'\-]+", text)
    keep = []
    for w in words:
        lw = w.lower()
        if lw in STOPWORDS:
            continue
        if len(lw) <= 2:
            continue
        keep.append(w)
    caps = [w for w in keep if (w[:1].isupper() or any(ch.isdigit() for ch in w))]
    base = caps if len(caps) >= 6 else keep
    seen, out = set(), []
    for w in base:
        lw = w.lower()
        if lw in seen:
            continue
        seen.add(lw)
        out.append(w)
        if len(out) >= max_words:
            break
    return out

def build_search_queries(user_text: str) -> Tuple[List[str], str]:
    user_text = normalize_spaces(user_text)
    sents = split_sentences(user_text)
    claim = sents[0] if sents else user_text[:180]
    claim = claim[:220]
    if len(claim) < 60 and len(sents) >= 2:
        claim = (sents[0] + " " + sents[1])[:240]
    kw = extract_keywords(user_text, max_words=12)
    kw_query = " ".join(kw)
    quoted = f"\"{claim}\"" if len(claim) <= 180 else f"\"{claim[:170]}\""
    queries = []
    for q in [quoted, claim, kw_query]:
        q = normalize_spaces(q)
        if q and q not in queries:
            queries.append(q)
    if len(queries) == 1:
        queries.append(claim)
    return queries, claim


# ----------------------------
# Unstructured input gate (prevents unreliable verdicts)
# ----------------------------
def looks_unstructured(text: str) -> bool:
    text = normalize_spaces(text)
    if len(text) < 35:
        return True
    # too many emojis/symbols or mostly lower-case slang
    non_alnum = sum(1 for c in text if not c.isalnum() and c not in " .,:;!?-'\"()")
    if non_alnum > 18:
        return True
    # no capitalized tokens and no numbers → weak searchability
    has_caps = bool(re.search(r"\b[A-Z][a-z]{2,}\b", text))
    has_num = bool(re.search(r"\d", text))
    if not has_caps and not has_num and len(text) < 120:
        return True
    return False


# ----------------------------
# Evidence representation
# ----------------------------
@dataclass
class Evidence:
    title: str
    snippet: str
    url: str
    source: str
    score: float  # your existing match score if available


# ----------------------------
# Main verifier class
# ----------------------------
class TextClaimVerifier:
    def __init__(self):
        self.embedder = SentenceTransformer(EMBED_MODEL_NAME)
        self.nli_tokenizer = AutoTokenizer.from_pretrained(NLI_MODEL_NAME)
        self.nli_model = AutoModelForSequenceClassification.from_pretrained(NLI_MODEL_NAME).to(DEVICE)
        self.nli_model.eval()

    def _to_evidence(self, matches: List[Dict[str, Any]]) -> List[Evidence]:
        ev = []
        for m in matches or []:
            ev.append(Evidence(
                title=str(m.get("title", "")),
                snippet=str(m.get("snippet", m.get("summary", ""))),
                url=str(m.get("url", "")),
                source=str(m.get("source", "")),
                score=float(m.get("score", 0.0))
            ))
        return ev

    def semantic_rerank(self, claim: str, evidence: List[Evidence]) -> List[Tuple[Evidence, float]]:
        claim = normalize_spaces(claim)
        if not claim or not evidence:
            return []

        ev_texts = []
        for e in evidence:
            t = normalize_spaces(e.title)
            s = normalize_spaces(e.snippet)
            ev_texts.append((t + " " + s).strip())

        claim_emb = self.embedder.encode(claim, convert_to_tensor=True)
        ev_embs = self.embedder.encode(ev_texts, convert_to_tensor=True)

        sims = util.cos_sim(claim_emb, ev_embs)[0].tolist()
        ranked = sorted(zip(evidence, sims), key=lambda x: x[1], reverse=True)
        return ranked

    @torch.no_grad()
    def nli_score(self, claim: str, premise: str) -> Tuple[str, float]:
        # premise = evidence text, hypothesis = claim
        inputs = self.nli_tokenizer(
            premise,
            claim,
            truncation=True,
            max_length=384,
            return_tensors="pt"
        ).to(DEVICE)
        logits = self.nli_model(**inputs).logits[0]
        probs = torch.softmax(logits, dim=-1).detach().cpu().tolist()
        label_id = int(torch.argmax(torch.tensor(probs)).item())
        label = LABEL_MAP[label_id]
        conf = float(probs[label_id])
        return label, conf

    def verify(
        self,
        user_text: str,
        search_fn,
        min_semantic: float = 0.55,
        entail_threshold: float = 0.70,
        contradict_threshold: float = 0.70,
        max_evidence: int = 8
    ) -> Dict[str, Any]:

        user_text = normalize_spaces(user_text)
        queries, extracted_claim = build_search_queries(user_text)

        if looks_unstructured(user_text):
            return {
                "error": False,
                "verification_method": "text",
                "query_used": queries[0] if queries else "",
                "extracted_claim": extracted_claim,
                "verified": False,
                "final_label": "UNVERIFIED",
                "final_confidence": 0.52,
                "explanation": "Input is too incomplete/unclear to verify reliably. Add names, place, and what happened.",
                "top_matches": [],
                "nli": {"best_label": "NEUTRAL", "best_confidence": 0.0}
            }

        # 1) Collect matches from your trusted-source search (existing)
        all_matches = []
        for q in queries:
            matches = search_fn(q)  # must return list[dict]
            if matches:
                for m in matches:
                    m["query_used"] = q
                all_matches.extend(matches)

        # Deduplicate by URL
        seen = set()
        dedup = []
        for m in all_matches:
            u = str(m.get("url", "")).strip()
            if not u or u in seen:
                continue
            seen.add(u)
            dedup.append(m)

        evidence = self._to_evidence(dedup)
        if not evidence:
            return {
                "error": False,
                "verification_method": "text",
                "query_used": queries[0] if queries else "",
                "extracted_claim": extracted_claim,
                "verified": False,
                "final_label": "UNVERIFIED",
                "final_confidence": 0.55,
                "explanation": "No matching coverage found in trusted sources.",
                "top_matches": [],
                "nli": {"best_label": "NEUTRAL", "best_confidence": 0.0}
            }

        # 2) Semantic rerank (paraphrase robustness)
        ranked_sem = self.semantic_rerank(extracted_claim, evidence)
        ranked_sem = [(e, s) for (e, s) in ranked_sem if s >= min_semantic]
        ranked_sem = ranked_sem[:max_evidence]

        # If semantic ranking still weak, keep unverified (avoid false positives)
        if not ranked_sem:
            # fallback: return top raw matches (by original score), but unverified
            evidence.sort(key=lambda x: x.score, reverse=True)
            top = evidence[:5]
            return {
                "error": False,
                "verification_method": "text",
                "query_used": queries[0] if queries else "",
                "extracted_claim": extracted_claim,
                "verified": False,
                "final_label": "UNVERIFIED",
                "final_confidence": 0.56,
                "explanation": "Some results found, but they are not semantically close enough to the claim.",
                "top_matches": [
                    {"title": t.title, "url": t.url, "source": t.source, "snippet": t.snippet, "score": t.score}
                    for t in top
                ],
                "nli": {"best_label": "NEUTRAL", "best_confidence": 0.0}
            }

        # 3) NLI: entail / contradict / neutral (true claim verification)
        best = {"label": "NEUTRAL", "conf": 0.0, "evidence": None, "semantic": 0.0}
        for e, sem in ranked_sem:
            premise = normalize_spaces((e.title + " " + e.snippet).strip())
            if not premise:
                continue
            label, conf = self.nli_score(extracted_claim, premise)
            # prioritize high-confidence contradiction/entailment
            if conf > best["conf"]:
                best = {"label": label, "conf": conf, "evidence": e, "semantic": sem}

        # 4) Decision policy
        if best["label"] == "ENTAILMENT" and best["conf"] >= entail_threshold:
            final_label = "REAL"
            verified = True
            confidence = min(0.95, 0.60 + 0.35 * best["conf"] + 0.10 * best["semantic"])
            explanation = "Trusted coverage supports the claim (entailment)."
        elif best["label"] == "CONTRADICTION" and best["conf"] >= contradict_threshold:
            final_label = "FAKE"
            verified = True
            confidence = min(0.95, 0.60 + 0.35 * best["conf"] + 0.10 * best["semantic"])
            explanation = "Trusted coverage contradicts the claim."
        else:
            final_label = "UNVERIFIED"
            verified = False
            confidence = max(0.55, 0.50 + 0.25 * best["conf"] + 0.10 * best["semantic"])
            explanation = "Trusted sources found, but they don't clearly support or refute the exact claim."

        # Build top_matches output
        top_out = []
        for e, sem in ranked_sem[:5]:
            top_out.append({
                "title": e.title,
                "url": e.url,
                "source": e.source,
                "snippet": e.snippet,
                "score": round(float(e.score), 4),
                "semantic": round(float(sem), 4),
            })

        return {
            "error": False,
            "verification_method": "text",
            "query_used": queries[0] if queries else "",
            "extracted_claim": extracted_claim,
            "verified": verified,
            "final_label": final_label,
            "final_confidence": round(float(confidence), 3),
            "explanation": explanation,
            "top_matches": top_out,
            "nli": {
                "best_label": best["label"],
                "best_confidence": round(float(best["conf"]), 4),
                "best_semantic": round(float(best["semantic"]), 4),
            }
        }
