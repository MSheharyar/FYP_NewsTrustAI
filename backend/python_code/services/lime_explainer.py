import logging
import os

import numpy as np
from lime.lime_text import LimeTextExplainer

logger = logging.getLogger(__name__)

# 300 samples was the original default but causes ~30 s on CPU (300 BERT calls).
# 100 is stable enough for top-5 word highlights and cuts latency by 3×.
# Override with LIME_NUM_SAMPLES env var if needed.
_NUM_SAMPLES = int(os.getenv("LIME_NUM_SAMPLES", "100"))

# Initialize explainer (Index 0 = 'fake', Index 1 = 'real')
explainer = LimeTextExplainer(class_names=['fake', 'real'])

def get_fake_highlights(text: str, predict_proba_fn, top_k: int = 5) -> list:
    """
    Uses LIME to extract the top words contributing to a 'fake' verdict.

    predict_proba_fn: A function that takes a list of strings [text1, text2...]
                      and returns a 2D numpy array of probabilities like:
                      [[prob_fake, prob_real], [prob_fake, prob_real]]
    """
    try:
        exp = explainer.explain_instance(
            text,
            predict_proba_fn,
            labels=(0,),
            num_features=top_k,
            num_samples=_NUM_SAMPLES,
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
        logger.warning("LIME explainer failed: %s", e)
        return []
