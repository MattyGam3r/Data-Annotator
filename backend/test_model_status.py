#!/usr/bin/env python3
"""
Test script to check model status and readiness.
Run this while training is happening to see the status changes.
"""

import time
from yolo_model import YOLOModel
from few_shot_model import FewShotModelTrainer

def check_models():
    """Check the status of both models"""
    yolo_status = YOLOModel.get_model_status()
    few_shot_status = FewShotModelTrainer.get_model_status()
    
    print("\n--- YOLO Model Status ---")
    print(f"Training in progress: {yolo_status['training_in_progress']}")
    print(f"Progress: {yolo_status['progress'] * 100:.1f}%")
    print(f"Is available: {yolo_status['is_available']}")
    print(f"Is ready: {yolo_status.get('is_ready', False)}")
    
    print("\n--- Few-Shot Model Status ---")
    print(f"Training in progress: {few_shot_status['training_in_progress']}")
    print(f"Progress: {few_shot_status['progress'] * 100:.1f}%")
    print(f"Is available: {few_shot_status['is_available']}")
    print(f"Is ready: {few_shot_status.get('is_ready', False)}")
    
    return yolo_status, few_shot_status

if __name__ == "__main__":
    print("Model Status Monitor")
    print("-------------------")
    print("This script will check the status of both models every 5 seconds.")
    print("Press Ctrl+C to exit.")
    
    try:
        while True:
            check_models()
            time.sleep(5)
    except KeyboardInterrupt:
        print("\nExiting...") 