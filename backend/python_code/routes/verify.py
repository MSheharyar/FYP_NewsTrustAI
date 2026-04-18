from fastapi import APIRouter, Body
import numpy as np

# Import your existing services
from services.verification import hybrid_decision
from services.bert import bert_predict
from services.lime_explainer import get_fake_highlights

router = APIRouter()

def lime_predict_wrapper(texts: list) -> np.ndarray:
    """
    Takes a list of texts and returns a 2D numpy array: 
    [[prob_fake, prob_real], ...] 
    Using your existing bert_predict function.
    """
    probs = []
    for t in texts:
        # Call the existing ML inference function.
        # This function should internally handle English vs Urdu models on your AWS server.
        bert_res = bert_predict(t)
        
        # Get dictionary of probabilities
        prob_dict = bert_res.get("probabilities", {})
        
        # Default to 50/50 if probabilities are missing
        prob_fake = prob_dict.get("fake", 0.5)
        prob_real = prob_dict.get("real", 0.5)
        
        probs.append([prob_fake, prob_real])
        
    return np.array(probs)

@router.post("/verify-text")
def verify_text(payload: dict = Body(...)):
    text = (payload.get("text") or "").strip()
    query = (payload.get("query") or "").strip()
    
    # 1. Get the standard heuristic/hybrid decision
    result = hybrid_decision(text)
    
    # 2. Get the BERT ML prediction
    bert_res = bert_predict(text)
    
    if isinstance(result, dict):
        result["query_used"] = query if query else text
        
        # Sync BERT findings into the main result dictionary
        result["bert_label"] = bert_res.get("label")
        result["bert_confidence"] = bert_res.get("confidence")
        result["probabilities"] = bert_res.get("probabilities")
        
        # Overwrite label if BERT is confident it's fake
        # (This combines your hybrid logic with the ML logic)
        if result.get("bert_label") == "fake":
            result["final_label"] = "fake"
            
        # 3. Apply LIME Explainability if the final verdict is fake
        final_label = result.get("final_label", "unverified").lower()
        
        if final_label == "fake":
            # Extract top 5 fake-contributing words using LIME
            highlighted_words = get_fake_highlights(text, lime_predict_wrapper, top_k=5)
            
            result["highlighted_words"] = highlighted_words
            result["explanation_text"] = "These words had the highest influence on our AI models in classifying this claim as Fake/Misleading."
        else:
            result["highlighted_words"] = []
            result["explanation_text"] = ""

    return result
