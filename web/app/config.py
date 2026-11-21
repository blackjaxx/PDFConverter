"""全局配置 —— 全部通过环境变量覆盖，Docker 部署时最常用。"""
import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
WEB_DIR = BASE_DIR.parent
DATA_DIR = Path(os.environ.get("PDFCONV_DATA_DIR", WEB_DIR / "data"))
OUTPUT_DIR = DATA_DIR / "outputs"

# 上传与并发限制
UPLOAD_LIMIT_MB = int(os.environ.get("PDFCONV_UPLOAD_LIMIT_MB", "100"))
MAX_CONCURRENT = max(1, int(os.environ.get("PDFCONV_MAX_CONCURRENT", "2")))

# 可选访问令牌：设置后所有 /api/* 请求需携带 X-Access-Token 头或 ?token= 参数
ACCESS_TOKEN = os.environ.get("PDFCONV_ACCESS_TOKEN", "")

# DeepSeek（桌面版存 Keychain；Web 版放服务器环境变量，也可由前端按次携带）
DEEPSEEK_API_KEY = os.environ.get("DEEPSEEK_API_KEY", "")
DEEPSEEK_BASE_URL = os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com")
DEEPSEEK_MODEL = os.environ.get("DEEPSEEK_MODEL", "deepseek-chat")

# 子进程单命令超时（秒）
TOOL_TIMEOUT = int(os.environ.get("PDFCONV_TOOL_TIMEOUT", "600"))
