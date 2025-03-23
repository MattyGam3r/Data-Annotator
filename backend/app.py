import os
import sqlite3
from flask import Flask, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

#Store Uploads Here:
UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

#Sqlite database to hold the images
DATABASE = 'metadata.db'

@app.route("/")
def home():
    return jsonify({"message": "Hello from Flask!"})

def init_db():



@app.route("/upload", methods = ["POST"])
def upload_image():



if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)