import torch
from ultralytics import YOLO
import os

def test_model():
    # Test model loading
    model_path = 'model/last.pt'
    print(f'Model file exists: {os.path.exists(model_path)}')
    print(f'Model file size: {os.path.getsize(model_path) if os.path.exists(model_path) else "N/A"} bytes')

    # Load model
    try:
        model = YOLO(model_path) 
        print('Model loaded successfully')
        print(f'Model classes: {model.names}')
        print(f'Model device: {next(model.model.parameters()).device}')
        
        # Test on a training image (should detect something)
        print("\nTesting on training image cat.1.jpg...")
        results = model('datasets/train/images/cat.1.jpg', conf=0.001, iou=0.5, verbose=True)
        print(f'Results for cat.1.jpg: {len(results[0].boxes)} detections')
        if len(results[0].boxes) > 0:
            print(f'Confidence scores: {results[0].boxes.conf}')
            print(f'Classes: {results[0].boxes.cls}')
        else:
            print('No detections found')
            
        # Check model structure
        print(f'\nModel structure info:')
        print(f'Model type: {type(model.model)}')
        
    except Exception as e:
        print(f'Error: {e}')
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    test_model() 