import logging

from google import genai
from google.genai import types

from config.settings import GEMINI_API_KEY

logger = logging.getLogger(__name__)

_SYSTEM_PROMPT = """You are NewsTrust AI Assistant, an intelligent chatbot built into the NewsTrustAI fake news detection app.

Your primary roles:
1. Help users understand why a specific news claim was classified as fake or real
2. Teach practical tips for spotting misinformation and media manipulation
3. Guide users through the news verification process step by step
4. Explain AI-based verification results in simple, clear language
5. Provide misinformation awareness education

When a [Verification Context] block is included in the message, use it to give specific, targeted explanations about that particular result — reference the verdict, confidence, and reason directly.

Guidelines:
- Be concise, friendly, and helpful. Use bullet points for clarity.
- Never fabricate facts or make up sources. If unsure, say so honestly.
- Always encourage cross-referencing multiple trusted news sources.
- Focus on media literacy, critical thinking, and fact-checking skills.
- Keep responses under 200 words unless a detailed explanation is truly needed.
- When explaining why something is fake, reference common misinformation patterns (headline manipulation, image reuse, date tampering, selective quoting).
- When the user pastes a claim, help them think critically about it.

You are a specialized assistant for news verification and media literacy only. Politely redirect off-topic conversations back to these themes."""

_client: genai.Client | None = None


def _get_client() -> genai.Client:
    global _client
    if _client is None:
        if not GEMINI_API_KEY:
            raise RuntimeError("GEMINI_API_KEY is not configured in settings.")
        _client = genai.Client(api_key=GEMINI_API_KEY)
        logger.info("Gemini client initialised.")
    return _client


def chat_with_gemini(
    message: str,
    history: list[dict],
    context: str | None = None,
    db_articles: list[dict] | None = None,
) -> str:
    client = _get_client()

    history_contents = []
    for turn in history:
        role = turn.get("role")
        parts = turn.get("parts", [])
        if role in ("user", "model") and parts:
            history_contents.append(
                types.Content(
                    role=role,
                    parts=[types.Part(text=p) for p in parts if isinstance(p, str)],
                )
            )

    chat_session = client.chats.create(
        model="gemini-2.5-flash",
        history=history_contents,
        config=types.GenerateContentConfig(
            system_instruction=_SYSTEM_PROMPT,
        ),
    )

    parts: list[str] = []

    if context and context.strip():
        parts.append(f"[Verification Context]\n{context.strip()}")

    if db_articles:
        lines = ["[Relevant Articles from NewsTrustAI Database]"]
        for i, art in enumerate(db_articles, 1):
            lines.append(
                f"{i}. {art.get('title', '(no title)')}"
                f"\n   Source: {art.get('source') or 'Unknown'}"
                f"\n   URL: {art.get('url') or 'N/A'}"
                f"\n   Excerpt: {art.get('snippet') or ''}"
            )
        parts.append("\n".join(lines))

    parts.append(f"[User Question]\n{message}")

    user_input = "\n\n".join(parts)

    response = chat_session.send_message(user_input)
    return response.text
