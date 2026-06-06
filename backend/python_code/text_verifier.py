import re
import math
import threading
from dataclasses import dataclass
from typing import List, Dict, Any, Tuple, Optional

import torch
from transformers import AutoTokenizer, AutoModelForSequenceClassification
from sentence_transformers import SentenceTransformer, util

from config.settings import NLI_MODEL_NAME, EMBED_MODEL_NAME, MIN_TEXT_LEN

DEVICE = "cuda" if torch.cuda.is_available() else "cpu"

LABEL_MAP = {0: "CONTRADICTION", 1: "NEUTRAL", 2: "ENTAILMENT"}  # nli-MiniLM2 label order


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
_EMOJI_RE = re.compile(
    r'[\U0001F300-\U0001F9FF\U00002702-\U000027B0\U0001FA00-\U0001FA6F'
    r'\U0001FA70-\U0001FAFF\U00002500-\U00002BEF]'
)

def looks_unstructured(text: str) -> bool:
    text = normalize_spaces(text)
    if len(text) < MIN_TEXT_LEN:
        return True
    # 2+ emoji characters → treat as spam/slang
    if len(_EMOJI_RE.findall(text)) >= 2:
        return True
    # too many non-standard symbols
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

    @torch.no_grad()
    def nli_score_batch(self, claim: str, premises: List[str]) -> List[Tuple[str, float]]:
        """Score claim against multiple premises in one forward pass."""
        if not premises:
            return []
        inputs = self.nli_tokenizer(
            [claim] * len(premises),
            premises,
            truncation=True,
            max_length=384,
            padding=True,
            return_tensors="pt"
        ).to(DEVICE)
        logits = self.nli_model(**inputs).logits  # (N, 3)
        probs = torch.softmax(logits, dim=-1).detach().cpu()
        results = []
        for i in range(len(premises)):
            label_id = int(torch.argmax(probs[i]).item())
            label = LABEL_MAP[label_id]
            conf = float(probs[i][label_id].item())
            results.append((label, conf))
        return results

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
        sents = split_sentences(user_text)
        queries, extracted_claim = build_search_queries(user_text)
        # Collect up to 2 candidate claims for multi-sentence NLI selection.
        claim_candidates = [extracted_claim]
        if len(sents) >= 2 and sents[1] != extracted_claim and len(sents[1]) >= 30:
            claim_candidates.append(sents[1])

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

        # 3) NLI: batch scoring + vote aggregation.
        #
        # For multi-sentence input we try each claim candidate (up to 2) and
        # keep the one that produces the strongest decisive NLI signal.  This
        # prevents a neutral first sentence from masking a false second sentence.
        premises = [
            normalize_spaces((e.title + " " + e.snippet).strip())
            for e, _ in ranked_sem
        ]
        valid = [(p, e, sem) for p, (e, sem) in zip(premises, ranked_sem) if p]

        best_claim_candidate = extracted_claim
        best_entail = {"conf": 0.0, "evidence": None, "semantic": 0.0}
        best_contra = {"conf": 0.0, "evidence": None, "semantic": 0.0}
        best_any = {"label": "NEUTRAL", "conf": 0.0, "evidence": None, "semantic": 0.0}
        entail_score = 0.0
        contra_score = 0.0
        n_entail = 0
        confidence_boost = 0.0

        for candidate in claim_candidates:
            if not valid:
                break
            valid_premises = [p for p, _, _ in valid]
            nli_results = self.nli_score_batch(candidate, valid_premises)

            c_entail = 0.0
            c_contra = 0.0
            c_best_entail = {"conf": 0.0, "evidence": None, "semantic": 0.0}
            c_best_contra = {"conf": 0.0, "evidence": None, "semantic": 0.0}
            c_best_any = {"label": "NEUTRAL", "conf": 0.0, "evidence": None, "semantic": 0.0}
            c_n_entail = 0

            for (label, conf), (_, e, sem) in zip(nli_results, valid):
                weight = conf * (0.7 + 0.3 * sem)
                if label == "ENTAILMENT":
                    c_entail += weight
                    c_n_entail += 1
                    if conf > c_best_entail["conf"]:
                        c_best_entail = {"conf": conf, "evidence": e, "semantic": sem}
                elif label == "CONTRADICTION":
                    c_contra += weight
                    if conf > c_best_contra["conf"]:
                        c_best_contra = {"conf": conf, "evidence": e, "semantic": sem}
                if conf > c_best_any["conf"]:
                    c_best_any = {"label": label, "conf": conf, "evidence": e, "semantic": sem}

            # Pick this candidate if it has a stronger decisive signal than current best.
            decisive = max(c_entail, c_contra)
            prev_decisive = max(entail_score, contra_score)
            if decisive > prev_decisive:
                best_claim_candidate = candidate
                entail_score = c_entail
                contra_score = c_contra
                best_entail = c_best_entail
                best_contra = c_best_contra
                best_any = c_best_any
                n_entail = c_n_entail

        extracted_claim = best_claim_candidate

        # Consensus decision: the winner must dominate or be the only signal
        total_decisive = entail_score + contra_score
        entail_ratio = entail_score / total_decisive if total_decisive > 0 else 0.5

        if (best_entail["conf"] >= entail_threshold and
                (entail_ratio >= 0.55 or contra_score == 0.0)):
            best = {"label": "ENTAILMENT", **best_entail}
            # Small bonus per additional supporting piece of evidence (cap +5%)
            confidence_boost = min(0.05, 0.012 * max(0, n_entail - 1))
        elif (best_contra["conf"] >= contradict_threshold and
                (entail_ratio <= 0.45 or entail_score == 0.0)):
            best = {"label": "CONTRADICTION", **best_contra}
        else:
            best = best_any

        # 4) Decision policy
        if best["label"] == "ENTAILMENT" and best["conf"] >= entail_threshold:
            final_label = "REAL"
            verified = True
            confidence = min(0.95, 0.60 + 0.35 * best["conf"] + 0.10 * best["semantic"] + confidence_boost)
            explanation = "Trusted coverage supports the claim (entailment)."
        elif best["label"] == "CONTRADICTION" and best["conf"] >= contradict_threshold:
            final_label = "FAKE"
            verified = True
            confidence = min(0.95, 0.60 + 0.35 * best["conf"] + 0.10 * best["semantic"])
            explanation = "Trusted coverage contradicts the claim."
        else:
            final_label = "UNVERIFIED"
            verified = False
            confidence = max(0.55, 0.50 + 0.25 * best["conf"] + 0.10 * best.get("semantic", 0.0))
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

# ----------------------------
# Global Instance for API
# ----------------------------
_verifier_lock = threading.Lock()
_global_verifier: Optional[TextClaimVerifier] = None

def get_text_verifier() -> TextClaimVerifier:
    global _global_verifier
    if _global_verifier is not None:
        return _global_verifier
        
    with _verifier_lock:
        if _global_verifier is None:
            try:
                _global_verifier = TextClaimVerifier()
            except Exception as e:
                print(f"Failed to initialize TextClaimVerifier: {e}")
                raise
        return _global_verifier

def warmup_text_verifier() -> bool:
    try:
        get_text_verifier()
        return True
    except Exception:
        return False

