# Data Annotator - User Guide

## What the Feature Does

The Data Annotator is an AI-powered image annotation tool designed to streamline the process of creating training datasets for machine learning models. It combines a fast Flutter web frontend with a Flask backend powered by YOLO (You Only Look Once) object detection to provide efficient, semi-automated image annotation capabilities.

**Key Features:**
- **Interactive Image Annotation**: Draw bounding boxes on images with mouse/touch
- **AI-Assisted Predictions**: YOLO and Few-Shot models provide automatic object detection
- **Real-time Model Training**: Train custom models on your annotated data
- **Data Augmentation**: Automatically generate additional training samples
- **Export Capabilities**: Export datasets in YOLO format for training
- **Uncertainty Scoring**: AI predictions include confidence scores for quality assessment

## How to Use It

### Basic Workflow

1. **Start the System**
   ```bash
   docker-compose up
   ```
   - Frontend: `http://localhost:8080`
   - Backend: `http://localhost:5001`

2. **Upload Images**
   - Click the upload button or drag images into the interface
   - Supported formats: JPG, PNG, JPEG
   - Images are stored in the backend's `uploads/` directory

3. **Annotate Images**
   - Select an image from the gallery
   - Draw bounding boxes by clicking and dragging on the image
   - Add labels to each bounding box
   - Use number keys (1-9, 0) for quick tag selection from frequent tags

4. **Review AI Predictions**
   - Toggle between YOLO, Few-Shot, or both model predictions
   - AI predictions appear in orange (unverified) or green (verified)
   - Human annotations appear in blue
   - Verify AI predictions by clicking on them

5. **Train Models**
   - Mark images as "complete" when finished annotating
   - Click the training button to start model training
   - Monitor training progress in real-time
   - Models automatically retrain on new data

6. **Export Dataset**
   - Click the export button to download YOLO-format dataset
   - Dataset includes images, labels, and configuration files

### Advanced Features

**Data Augmentation:**
- Automatically generate variations of annotated images
- Increases training dataset size
- Applied to verified annotations only

**Batch Processing:**
- Process multiple images simultaneously
- AI predictions for entire batches
- Bulk annotation workflows

**Uncertainty Scoring:**
- AI predictions include confidence scores
- Helps identify low-confidence detections
- Quality assessment for training data

## Available Options or Modes

### Model Display Modes
- **YOLO Only**: Show only YOLO model predictions
- **Few-Shot Only**: Show only Few-Shot model predictions  
- **Both**: Display predictions from both models

### Training Modes
- **Manual Training**: Trigger training manually via button
- **Auto-Training**: Automatic training when sufficient data is available
- **Incremental Training**: Retrain on new data while preserving previous learning

### Export Options
- **YOLO Format**: Standard YOLO dataset export
- **Complete Dataset**: Images + labels + configuration files
- **ZIP Archive**: Compressed dataset for easy sharing

## Expected Input

### Image Requirements
- **Formats**: JPG, PNG, JPEG
- **Size**: No strict limits, but recommended < 10MB per image
- **Content**: Any images requiring object detection annotation
- **Quality**: Clear, well-lit images work best

### Annotation Requirements
- **Bounding Boxes**: Rectangular regions around objects
- **Labels**: Text descriptions of object classes
- **Verification**: Mark AI predictions as verified/unverified
- **Completeness**: Mark images as fully annotated when done

## Expected Output

### Immediate Outputs
- **Visual Annotations**: Bounding boxes displayed on images
- **Label Files**: YOLO-format text files with coordinates
- **Confidence Scores**: Uncertainty metrics for AI predictions
- **Training Progress**: Real-time model training status

### Exported Outputs
- **YOLO Dataset**: Complete training dataset in YOLO format
- **Configuration Files**: `dataset.yaml` with class mappings
- **Model Files**: Trained YOLO models (`.pt` files)
- **Augmented Data**: Additional training samples

### Data Structure
```
yolo_dataset.zip/
├── data/
│   ├── images/          # Original and augmented images
│   ├── labels/          # YOLO-format annotation files
│   └── dataset.yaml     # Dataset configuration
```

## Limitations or Notes

### Technical Limitations
- **GPU Required**: NVIDIA GPU recommended for optimal performance
- **Memory Usage**: Large datasets may require significant RAM
- **Training Time**: Model training can take 10-60 minutes depending on dataset size
- **Browser Compatibility**: Modern browsers required for web interface

### Data Limitations
- **Minimum Dataset**: At least 10-20 images per class recommended
- **Class Consistency**: Consistent labeling improves model performance
- **Image Quality**: Poor quality images may affect AI predictions
- **Annotation Quality**: Accurate bounding boxes essential for good training

### Operational Notes
- **Offline Operation**: Works completely offline once started
- **Data Persistence**: Annotations stored in SQLite database
- **Model Caching**: Trained models cached for faster predictions
- **Error Recovery**: System can recover from training interruptions

## Entry Point

### For Users
- **Web Interface**: `http://localhost:8080` (main entry point)
- **Docker Command**: `docker-compose up` (starts entire system)

### For Developers
- **Frontend Entry**: `data_annotator/lib/main.dart` (Flutter app)
- **Backend Entry**: `backend/app.py` (Flask server)
- **Model Training**: `backend/yolo_model.py` (YOLO implementation)
- **Data Processing**: `backend/few_shot_model.py` (Few-Shot learning)

### API Endpoints
- **Upload**: `POST /upload` - Upload images
- **Images**: `GET /images` - Retrieve annotated images
- **Save**: `POST /save_annotations` - Save annotations
- **Train**: `POST /train_model` - Start model training
- **Predict**: `POST /predict` - Get AI predictions
- **Export**: `GET /export_yolo` - Export dataset

### Configuration Files
- **Docker**: `docker-compose.yml` - System orchestration
- **Frontend**: `data_annotator/pubspec.yaml` - Flutter dependencies
- **Backend**: `backend/requirements.txt` - Python dependencies
- **Model**: `model/classes.json` - Class mappings

---

**Note**: This system is designed for research and educational purposes. For production use, consider additional security, scalability, and backup measures. 