import json
import os
from collections import defaultdict
from typing import Dict, List, Tuple

from services.verification import hybrid_decision
from services.bert import bert_predict

def load_test_dataset(file_path: str) -> List[Dict]:
    """Load test dataset from JSON file."""
    with open(file_path, 'r', encoding='utf-8') as f:
        return json.load(f)

def normalize_label(label: str) -> str:
    """Normalize labels to real/fake/mixed."""
    label = label.lower().strip()
    if label in ['real', 'true']:
        return 'real'
    elif label in ['fake', 'false']:
        return 'fake'
    elif label == 'mixed':
        return 'mixed'
    else:
        return 'unverified'

def evaluate_pipeline(dataset: List[Dict], pipeline: str = 'hybrid') -> Dict:
    """
    Evaluate a pipeline on the dataset.
    Pipelines: 'hybrid', 'bert_only', 'hybrid_no_bert'
    """
    results = []
    for i, item in enumerate(dataset):
        claim = item['claim']
        true_label = normalize_label(item['label'])

        try:
            print(f"Evaluating claim {i+1}/{len(dataset)}: {claim[:50]}...")
            if pipeline == 'hybrid':
                result = hybrid_decision(claim)
                pred_label = normalize_label(result.get('authenticity', 'unverified'))
            elif pipeline == 'bert_only':
                bert_res = bert_predict(claim)
                pred_label = normalize_label(bert_res.get('label', 'unverified'))
            elif pipeline == 'hybrid_no_bert':
                # Simulate hybrid without BERT
                result = hybrid_decision(claim)
                if result.get('verification_method') in ['bert_only', 'db_and_bert_conflict', 'factcheck_and_bert_conflict']:
                    pred_label = 'unverified'
                else:
                    pred_label = normalize_label(result.get('authenticity', 'unverified'))
            else:
                raise ValueError(f"Unknown pipeline: {pipeline}")
        except Exception as e:
            print(f"Error evaluating claim '{claim[:50]}...': {e}")
            pred_label = 'error'

        results.append({
            'claim': claim,
            'true_label': true_label,
            'pred_label': pred_label,
            'pipeline': pipeline
        })

    return compute_metrics(results)

def compute_metrics(results: List[Dict]) -> Dict:
    """Compute accuracy, precision, recall, F1 for real/fake classification."""
    # Focus on real vs fake, treat mixed/unverified as neutral
    tp = fp = tn = fn = 0
    for r in results:
        true = r['true_label']
        pred = r['pred_label']

        if true == 'real' and pred == 'real':
            tp += 1
        elif true == 'real' and pred == 'fake':
            fn += 1
        elif true == 'fake' and pred == 'fake':
            tn += 1
        elif true == 'fake' and pred == 'real':
            fp += 1
        # Ignore mixed/unverified for binary metrics

    accuracy = (tp + tn) / len(results) if results else 0
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0
    f1 = 2 * precision * recall / (precision + recall) if (precision + recall) > 0 else 0

    # Per-label accuracy
    label_counts = defaultdict(int)
    correct_counts = defaultdict(int)
    for r in results:
        label_counts[r['true_label']] += 1
        if r['true_label'] == r['pred_label']:
            correct_counts[r['true_label']] += 1

    per_label_accuracy = {label: correct_counts[label] / count if count > 0 else 0
                         for label, count in label_counts.items()}

    return {
        'total_samples': len(results),
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'f1_score': f1,
        'tp': tp, 'fp': fp, 'tn': tn, 'fn': fn,
        'per_label_accuracy': per_label_accuracy
    }

def main():
    dataset_path = os.path.join(os.path.dirname(__file__), 'test_dataset.json')
    dataset = load_test_dataset(dataset_path)

    pipelines = ['hybrid', 'bert_only', 'hybrid_no_bert']
    all_metrics = {}

    for pipeline in pipelines:
        print(f"Evaluating {pipeline} pipeline...")
        metrics = evaluate_pipeline(dataset, pipeline)
        all_metrics[pipeline] = metrics
        print(f"  Accuracy: {metrics['accuracy']:.2%}")
        print(f"  Precision: {metrics['precision']:.2%}")
        print(f"  Recall: {metrics['recall']:.2%}")
        print(f"  F1 Score: {metrics['f1_score']:.2%}")
        print(f"  Per-label accuracy: {metrics['per_label_accuracy']}")
        print()

    # Save results
    output_path = os.path.join(os.path.dirname(__file__), 'evaluation_results.json')
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(all_metrics, f, indent=2)
    print(f"Results saved to {output_path}")

if __name__ == '__main__':
    main()