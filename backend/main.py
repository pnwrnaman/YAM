
import os
import json
from datetime import date
from typing import List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field

from langchain_nvidia_ai_endpoints import ChatNVIDIA
from langchain_core.tools import tool
from langchain_core.prompts import ChatPromptTemplate, MessagesPlaceholder
from langchain_classic.agents import AgentExecutor, create_tool_calling_agent


# --------------------------------------------------------------------------
# LLM
# --------------------------------------------------------------------------

NVIDIA_API_KEY = os.environ.get("NVIDIA_API_KEY")

llm = ChatNVIDIA(
    model="nvidia/nemotron-3-super-120b-a12b",
    api_key=NVIDIA_API_KEY,
    temperature=0.3,
    top_p=0.7,
    max_completion_tokens=2048,
)


# --------------------------------------------------------------------------
# Pydantic models
# --------------------------------------------------------------------------

class ItineraryRequest(BaseModel):
    origin: str = Field(..., description="City/town the traveler starts from")
    destination: str = Field(..., description="Mountain, peak, or trekking region")
    start_date: date = Field(..., description="Trip start date (YYYY-MM-DD)")
    duration_days: int = Field(..., gt=0, description="Total trip length in days")
    budget: float = Field(..., gt=0, description="Total budget in USD")
    trek_difficulty: str = Field(..., description="easy | moderate | hard | technical")


class TimelineStep(BaseModel):
    day_number: int
    time: str
    title: str
    description: str
    altitude_gain: Optional[str] = None
    transport_mode: Optional[str] = None
    cost: Optional[float] = None


class ItineraryResponse(BaseModel):
    total_estimated_cost: float
    timeline: List[TimelineStep]


# --------------------------------------------------------------------------
# Tools
# --------------------------------------------------------------------------

@tool
def get_basecamp_transit(origin: str, destination: str) -> str:
    """
    Look up ground/air transit options and approximate costs/durations
    between an origin city and a mountain basecamp/trailhead town.
    Returns a structured text summary the agent can reason over.
    """
    return (
        f"TRANSIT OPTIONS: {origin} -> {destination} basecamp\n"
        f"- Option A: Domestic flight to nearest regional airport, then jeep transfer "
        f"to trailhead. Est. duration: 6-9 hrs total. Est. cost: $180-260 USD.\n"
        f"- Option B: Overnight bus/train to nearest hub town, then shared jeep to "
        f"trailhead. Est. duration: 14-18 hrs total. Est. cost: $40-70 USD.\n"
        f"- Option C: Private hired vehicle door-to-door. Est. duration: 10-14 hrs. "
        f"Est. cost: $150-220 USD.\n"
        f"Notes: Roads to remote trailheads are frequently weather-dependent; "
        f"build in a 1-day buffer before the trek start."
    )


@tool
def analyze_trail_elevation(destination: str, trek_difficulty: str, duration_days: int) -> str:
    """
    Analyze the trail's elevation profile for the given destination and
    difficulty level, returning a day-by-day altitude gain/loss and
    acclimatization guidance as structured text.
    """
    base_gain = {
        "easy": 300,
        "moderate": 550,
        "hard": 800,
        "technical": 1000,
    }.get(trek_difficulty.lower(), 500)

    lines = [f"ELEVATION PROFILE: {destination} ({trek_difficulty}, {duration_days} days)"]
    for day in range(1, duration_days + 1):
        if day % 3 == 0:
            lines.append(
                f"Day {day}: Acclimatization/rest day, altitude gain ~0m, "
                f"short exploratory hike only."
            )
        else:
            gain = base_gain + (day * 20)
            lines.append(
                f"Day {day}: Ascend approx {gain}m, trail gradient moderate-to-steep, "
                f"watch for AMS symptoms above 3500m."
            )
    lines.append(
        "Guidance: Follow 'climb high, sleep low' where possible; hydrate 3-4L/day; "
        "descend immediately if severe AMS symptoms appear."
    )
    return "\n".join(lines)


@tool
def check_mountain_weather(destination: str, start_date: str, duration_days: int) -> str:
    """
    Retrieve a simulated multi-day mountain weather outlook for the
    destination starting on the given date, including temperature ranges,
    precipitation risk, and wind conditions relevant to trek planning.
    """
    lines = [f"WEATHER OUTLOOK: {destination} starting {start_date} ({duration_days} days)"]
    for day in range(1, duration_days + 1):
        lines.append(
            f"Day {day}: Daytime {10 - day}C / Night {-5 - day}C, "
            f"precipitation chance {15 + (day % 4) * 10}%, "
            f"wind {10 + (day % 5) * 5} km/h. "
            f"{'Clear skies expected, good visibility.' if day % 2 == 0 else 'Partial cloud cover, possible afternoon snow at altitude.'}"
        )
    lines.append(
        "Advisory: Mountain weather changes rapidly; carry layered insulation, "
        "a waterproof shell, and monitor local forecasts daily."
    )
    return "\n".join(lines)


@tool
def generate_gear_and_budget(trek_difficulty: str, duration_days: int, budget: float) -> str:
    """
    Generate a recommended gear checklist and a cost breakdown (permits,
    guide/porter fees, food, lodging, gear rental) that fits within the
    stated difficulty level, trip length, and total budget.
    """
    per_day_estimates = {
        "easy": 35,
        "moderate": 55,
        "hard": 80,
        "technical": 120,
    }
    per_day = per_day_estimates.get(trek_difficulty.lower(), 60)
    trek_cost = per_day * duration_days
    permit_cost = 40 if trek_difficulty.lower() in ("hard", "technical") else 20
    gear_rental = 60 if trek_difficulty.lower() in ("hard", "technical") else 25

    total = trek_cost + permit_cost + gear_rental

    lines = [
        f"GEAR & BUDGET BREAKDOWN ({trek_difficulty}, {duration_days} days, budget ${budget:.2f})",
        f"- Guide/porter + lodging + food: ${trek_cost:.2f} (${per_day}/day)",
        f"- Permits & conservation fees: ${permit_cost:.2f}",
        f"- Gear rental (crampons, poles, insulated jacket): ${gear_rental:.2f}",
        f"- Estimated total: ${total:.2f}",
        (
            "- Budget status: "
            + (
                "WITHIN BUDGET"
                if total <= budget
                else f"OVER BUDGET by ${(total - budget):.2f}"
            )
        ),
        (
            "Essential gear checklist: insulated jacket, waterproof shell, trekking poles, "
            "sturdy boots, headlamp, water purification, first-aid kit, sun protection, "
            "sleeping bag rated to expected low temps."
        ),
    ]
    return "\n".join(lines)


TOOLS = [get_basecamp_transit, analyze_trail_elevation, check_mountain_weather, generate_gear_and_budget]


# --------------------------------------------------------------------------
# Agent setup
# --------------------------------------------------------------------------

AGENT_SYSTEM_PROMPT = """You are YAM (Yet Another Mountaineer), an expert trekking and \
mountaineering itinerary planner. Given a trip request, use the available tools to \
gather transit options, elevation/acclimatization data, weather outlook, and a gear/budget \
breakdown. Then synthesize ALL of that tool output into a detailed, day-by-day itinerary.

You MUST call every tool at least once before producing your final answer.

Your final answer must be a single JSON object with EXACTLY this shape and no extra \
commentary, markdown fences, or prose outside the JSON:

{{
  "total_estimated_cost": <number>,
  "timeline": [
    {{
      "day_number": <int>,
      "time": "<e.g. '06:00' or 'Morning'>",
      "title": "<short step title>",
      "description": "<what happens in this step>",
      "altitude_gain": "<e.g. '450m' or null>",
      "transport_mode": "<e.g. 'jeep', 'foot', 'flight' or null>",
      "cost": <number or null>
    }}
  ]
}}

Cover the transit day(s), each trek day (including rest/acclimatization days), and return \
a total_estimated_cost consistent with the budget breakdown tool's output.
"""

prompt = ChatPromptTemplate.from_messages([
    ("system", AGENT_SYSTEM_PROMPT),
    ("human", "{input}"),
    MessagesPlaceholder(variable_name="agent_scratchpad"),
])

agent = create_tool_calling_agent(llm, TOOLS, prompt)
agent_executor = AgentExecutor(agent=agent, tools=TOOLS, verbose=True, max_iterations=8)


# --------------------------------------------------------------------------
# FastAPI app
# --------------------------------------------------------------------------

app = FastAPI(title="YAM - Yet Another Mountaineer", version="1.0.0")

# Allow all origins so the Flutter client (mobile/web/desktop) can connect
# from any origin without CORS friction.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _extract_json_block(text: str) -> dict:
    """Best-effort extraction of a JSON object from raw agent text output."""
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]
    start = text.find("{")
    end = text.rfind("}")
    if start == -1 or end == -1 or end < start:
        raise ValueError("No JSON object found in agent output.")
    return json.loads(text[start:end + 1])


@app.post("/generate_itinerary", response_model=ItineraryResponse)
async def generate_itinerary(request: ItineraryRequest) -> ItineraryResponse:
    """
    Generate a full mountaineering/trekking itinerary by running the LangChain
    tool-calling agent over transit, elevation, weather, and budget tools,
    then parsing the agent's final JSON output into a structured
    ItineraryResponse.
    """
    user_input = (
        f"Plan a trek from {request.origin} to {request.destination}, "
        f"starting {request.start_date.isoformat()}, lasting {request.duration_days} days, "
        f"with a total budget of ${request.budget:.2f} USD, at "
        f"'{request.trek_difficulty}' difficulty level."
    )

    try:
        result = await agent_executor.ainvoke({"input": user_input})
        raw_output = result.get("output", "")
        parsed = _extract_json_block(raw_output)
        return ItineraryResponse(**parsed)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=f"Failed to generate itinerary: {exc}",
        )


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "service": "YAM"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
