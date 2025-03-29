import os
import sqlite3
from flask import Flask, jsonify, Response, request
from flask_cors import CORS, cross_origin
from werkzeug import utils

app = Flask(__name__)
cors = CORS(app, 
            origins=["http://localhost:8080", "localhost:8080"],
            methods=["POST", "OPTIONS"],
            allow_headers=["Content-Type"])

#Store Uploads Here:
UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

#Sqlite database to hold the images
DATABASE = 'metadata.db'


@app.route("/")
def home():
    return jsonify({"message": "Hello from Flask!"})

#def init_db():



@app.route("/upload", methods = ["POST"])
def upload_image():
        imagefile = request.files['image']
        #TODO: Get secure filename eventually
        #filename = werkzeug.utils.secure_filename(imagefile.filename)
        imagefile.save("./uploads/" + imagefile.filename)
        response = jsonify({
            "message": "Image(s) Uploaded Successfully"
        })
        return response



if __name__ == "__main__":
    app.run(debug = True, host="0.0.0.0", port=5000)