import numpy as np
from lime.lime_text import LimeTextExplainer
import re

# Initialize explainer (Index 0 = 'fake', Index 1 = 'real')
explainer = LimeTextExplainer(class_names=['fake', 'real'])

def is_urdu(text: str) -> bool:
    """Helper to detect if text contains Urdu/Arabic script."""
    urdu_chars = re.findall(r'[\u0600-\u06FF]', text)
    return len(urdu_chars) > 0

def get_fake_highlights(text: str, predict_proba_fn, top_k: int = 5) -> list:
    """
    Uses LIME to extract the top words contributing to a 'fake' verdict.
    
    predict_proba_fn: A function that takes a list of strings [text1, text2...]
                      and returns a 2D numpy array of probabilities like:
                      [[prob_fake, prob_real], [prob_fake, prob_real]]
    """
    try:
        # Generate the explanation
        # Notice we use fewer samples (num_samples=100) to ensure the API stays fast for mobile
        exp = explainer.explain_instance(
            text, 
            predict_proba_fn, 
            labels=(0,),          # explicitly ask it to explain class 0 ('fake')
            num_features=top_k,
            num_samples=100       
        )
        
        # Extract weights specifically for the "fake" class (class 0)
        fake_weights = exp.as_list(label=0)
        
        highlighted_words = []
        for word, weight in fake_weights:
            # Positive weight means it actively pushed the model towards 'fake'
            if weight > 0:
                highlighted_words.append(word)
                
        return highlighted_words
        
    except Exception as e:
        print(f"LIME Explainer Error: {e}")
        return []
