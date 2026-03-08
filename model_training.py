import os
import json
import requests
import cv2
import numpy as np
from tqdm import tqdm
from ultralytics import YOLO


URL = "https://raw.githubusercontent.com/garythung/trashnet/master/data/dataset-resized.zip"
r = requests.get(URL, stream = True)

if not os.path.exists("z.zip"):
  with open("z.zip", "wb") as f:
    for chunk in r.iter_content(1024):
      f.write(chunk)
  import zipfile
  with zipfile.ZipFile("z.zip", "r") as z:
    z.extractall("data")

if not os.path.exists("dataset"):
  os.makedirs("dataset/images/train")
  os.makedirs("dataset/images/val")
  os.makedirs("dataset/labels/train")
  os.makedirs("dataset/labels/val")
  for cat_id, cat in enumerate(['glass', 'paper', 'cardboard', 'plastic', 'metal', 'trash']):
    for i in range(600):
      split = "train" if np.random.rand() < 0.6 else "val"
      filename = cat + str(i) + ".jpg"
      if not os.path.exists("data/dataset-resized/" + cat + "/" + filename): continue
      img_out = os.path.join("dataset/images", split, filename)
      lbl_out = os.path.join("dataset/labels", split, filename.replace(".jpg", ".txt"))
      
      cv_img = cv2.imread("data/dataset-resized/" + cat + "/" + filename)
      h, w = cv_img.shape[:2]

      x, y, bw, bh = 0, 0, w, h
      xc, yc = (x + bw / 2) / w, (y + bh / 2) / h
      norm_w, norm_h = bw / w, bh / h

      with open(lbl_out, "a") as lf:
        lf.write(f"{cat_id} {xc} {yc} {norm_w} {norm_h}\n")

      cv2.imwrite(img_out, cv_img)

yolofile = "trash.yaml"
with open(yolofile, "w") as yf:
  yf.write("train: 'dataset/images/train'\n")
  yf.write("val: 'dataset/images/val'\n")
  yf.write(f"nc: 6\n")
  yf.write("names: ['glass', 'paper', 'cardboard', 'plastic', 'metal', 'trash']\n")

model = YOLO("yolov8n.pt")  # nano model for mobile
results = model.train(
    data=yolofile,
    epochs=15,
    imgsz=320,
    batch=32,
)
model.export(format="coreml", imgsz=320)
