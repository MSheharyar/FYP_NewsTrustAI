try:
    import shap
    _HAS_SHAP = True
except ImportError:
    _HAS_SHAP = False

import numpy as np

def get_fake_highlights(text: str, predict_proba_fn, top_k: int = 5) -> list:
    """
    Uses SHAP to extract the top words contributing to a 'fake' verdict.
    
    predict_proba_fn: A function that takes a list of strings [text1, text2...]
                      and returns a 2D numpy array of probabilities like:
                      [[prob_fake, prob_real], [prob_fake, prob_real]]
    """
    if not _HAS_SHAP:
        return []

    try:
        # SHAP's text explainer needs a masker. We use a simple whitespace masker.
        masker = shap.maskers.Text(r"\W") 
        
        # Initialize the explainer
        explainer = shap.Explainer(predict_proba_fn, masker, output_names=['fake', 'real'])
        
        # Generate the explanation for the single text
        shap_values = explainer([text])
        
        # shap_values.values shape: (1, num_words, 2)
        # Class 0 is 'fake'. We want words with positive SHAP values for class 0.
        values_for_fake = shap_values.values[0, :, 0]
        words = shap_values.data[0]
        
        # Pair words with their SHAP weights
        word_weights = []
        for word, weight in zip(words, values_for_fake):
            # Ignore purely whitespace/punctuation strings and only keep positive contributions
            if word.strip() and weight > 0:
                word_weights.append((word, weight))
                
        # Sort by weight descending (highest contribution first)
        word_weights.sort(key=lambda x: x[1], reverse=True)
        
        # Extract top_k words
        highlighted_words = [w[0] for w in word_weights[:top_k]]
        return highlighted_words
        
    except Exception as e:
        print(f"SHAP Explainer Error: {e}")
        return []
