# PDF Converter Web —— 单镜像部署（内置全部 CLI 工具）
FROM python:3.12-slim

# 转换引擎依赖：Poppler / qpdf / Ghostscript / Tesseract(含中文) / LibreOffice
RUN apt-get update && apt-get install -y --no-install-recommends \
        poppler-utils \
        qpdf \
        ghostscript \
        tesseract-ocr \
        tesseract-ocr-chi-sim \
        tesseract-ocr-eng \
        libreoffice-writer \
        libreoffice-calc \
        libreoffice-impress \
        fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
COPY static ./static

ENV PDFCONV_DATA_DIR=/data
VOLUME /data
EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
