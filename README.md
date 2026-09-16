# YAM (Your Auto Map) 🗺️🏔️

<img width="1710" height="1112" alt="Screenshot 2026-09-16 at 1 33 44 PM" src="https://github.com/user-attachments/assets/9a9556d9-9444-4cc5-a70d-f8a00e390d43" />


**YAM (Your Auto Map)** is an AI-powered trekking and travel itinerary generator designed for outdoor enthusiasts. Tell YAM where you want to go, and it will dynamically shape a paced, trail-aware itinerary complete with travel logistics, altitude gains, estimated costs (in ₹), and essential gear recommendations.

---

## ✨ Features
* **AI-Generated Itineraries:** Leverages LangChain agents to intelligently plan day-by-day travel routes.
* **Trail-Aware Planning:** Incorporates altitude gain, transport modes, and terrain difficulty.
* **Cost & Gear Estimation:** Automatically calculates projected trip costs in INR (₹) and suggests necessary trekking gear.
* **Beautiful Timeline UI:** A highly polished, responsive Flutter frontend that visualizes your journey step-by-step.
* **Custom AI Tools:** The backend agent uses custom-built tools to analyze elevations, check transit options, and retrieve mountain weather data.

---

## 🛠️ Tech Stack

**Frontend:**
* Flutter (Dart)
* Cross-platform UI (Desktop/Web/Mobile)

**Backend:**
* Python
* FastAPI & Uvicorn (REST API)
* Pydantic (Data validation)

**AI & Machine Learning:**
* LangChain (Tool-calling Agents & Orchestration)
* NVIDIA NIM Endpoints (`nvidia/nemotron-3-super-120b-a12b` LLM)

---

## 🚀 Getting Started

Follow these instructions to get a copy of the project up and running on your local machine.

### Prerequisites
* [Flutter SDK](https://flutter.dev/docs/get-started/install) installed.
* [Python 3.10+](https://www.python.org/downloads/) installed.
* An NVIDIA API Key.

### 1. Backend Setup (FastAPI + LangChain)

Navigate to your backend directory (if separated) or project root:
```bash
# Create and activate a virtual environment
python -m venv venv
source venv/bin/activate  # On Windows use: venv\Scripts\activate

# Install dependencies
pip install fastapi uvicorn pydantic langchain langchain-nvidia-ai-endpoints

# Set your NVIDIA API Key
export NVIDIA_API_KEY="your_nvidia_api_key_here"

# Run the FastAPI server
uvicorn main:app --reload --port 8000<img width="1710" height="1112" alt="Screenshot 2026-09-16 at 1 33 44 PM" src="https://github.com/user-attachments/assets/457ba823-a08d-4402-9655-785bfa69b239" />
