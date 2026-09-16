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
from dotenv import load_dotenv
load_dotenv()


import certifi
os.environ.setdefault("SSL_CERT_FILE", certifi.where())
os.environ.setdefault("REQUESTS_CA_BUNDLE", certifi.where())


# --------------------------------------------------------------------------
# LLM
# --------------------------------------------------------------------------

NVIDIA_API_KEY = os.environ.get("NVIDIA_API_KEY")

if not NVIDIA_API_KEY:
    raise RuntimeError(
        "NVIDIA_API_KEY is not set. Add it to backend/.env or export it "
        "in your shell before starting the server."
    )

llm = ChatNVIDIA(
    model="nvidia/nemotron-3-super-120b-a12b",
    api_key=NVIDIA_API_KEY,
    temperature=0.3,
    top_p=0.7,
    max_completion_tokens=8192,
    # Nemotron 3 Super is a reasoning model with "thinking" on by default.
    # We just need structured JSON out, not visible chain-of-thought, and
    # leaving thinking on was eating the token budget before the model ever
    # got to write the actual answer (causing "No JSON object found").
    chat_template_kwargs={"enable_thinking": False},
)


# --------------------------------------------------------------------------
# Pydantic models
# --------------------------------------------------------------------------

class ItineraryRequest(BaseModel):
    origin: str = Field(..., description="City/town the traveler starts from")
    destination: str = Field(..., description="Mountain, peak, or trekking region")
    start_date: date = Field(..., description="Trip start date (YYYY-MM-DD)")
    duration_days: int = Field(..., gt=0, description="Total trip length in days")
    budget: float = Field(..., gt=0, description="Total budget in INR")
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
    between an origin city and an Uttarakhand mountain basecamp/trailhead town.
    Returns a structured text summary with booking links.
    """
    return (
        f"TRANSIT OPTIONS: {origin} → {destination} (Uttarakhand)\n"
        f"- Option A: Train from {origin} to Haridwar/Rishikesh via IRCTC, "
        f"then shared jeep/Sumo to trailhead. "
        f"Est. duration: 8-14 hrs total. Est. cost: ₹800-₹2,500.\n"
        f"  Book train: https://www.irctc.co.in\n"
        f"- Option B: UPSRTC / UKRTC Volvo bus from {origin} to Rishikesh/Srinagar/Joshimath, "
        f"then local shared taxi to trailhead. "
        f"Est. duration: 10-16 hrs total. Est. cost: ₹600-₹1,800.\n"
        f"  Book bus: https://www.upsrtc.com | https://utconline.uk.gov.in\n"
        f"- Option C: Private hired Innova/Tempo Traveller door-to-door. "
        f"Est. duration: 8-12 hrs. Est. cost: ₹4,000-₹8,000 (one way, shareable).\n"
        f"  Book cab: https://www.savaari.com | https://www.makemytrip.com/cab\n"
        f"- Option D: Fly to Jolly Grant Airport (Dehradun), then taxi to trailhead. "
        f"Est. duration: 1.5 hr flight + 4-8 hrs road. Est. cost: ₹3,500-₹7,000 (flight) + ₹1,500-₹3,000 (taxi).\n"
        f"  Book flight: https://www.makemytrip.com | https://www.goindigo.in\n"
        f"Notes: Roads in Uttarakhand are frequently affected by landslides during monsoon "
        f"(Jul-Sep); check BRO road status. Build in a 1-day buffer before the trek start."
    )


@tool
def analyze_trail_elevation(destination: str, trek_difficulty: str, duration_days: int) -> str:
    """
    Analyze the trail's elevation profile for a given Uttarakhand destination
    and difficulty level, returning a day-by-day altitude gain/loss and
    acclimatization guidance as structured text.
    """
    base_gain = {
        "easy": 300,
        "moderate": 550,
        "hard": 800,
        "technical": 1000,
    }.get(trek_difficulty.lower(), 500)

    lines = [f"ELEVATION PROFILE: {destination}, Uttarakhand ({trek_difficulty}, {duration_days} days)"]
    for day in range(1, duration_days + 1):
        if day % 3 == 0:
            lines.append(
                f"Day {day}: Acclimatization/rest day, altitude gain ~0m, "
                f"short exploratory hike around camp or nearby bugyal (alpine meadow)."
            )
        else:
            gain = base_gain + (day * 20)
            lines.append(
                f"Day {day}: Ascend approx {gain}m, trail gradient moderate-to-steep, "
                f"watch for AMS symptoms above 3,500m."
            )
    lines.append(
        "Guidance: Follow 'climb high, sleep low' where possible; hydrate 3-4L/day; "
        "descend immediately if severe AMS symptoms appear. Carry Diamox as a precaution "
        "(consult doctor). BSNL/MTNL may have limited signal above treeline."
    )
    return "\n".join(lines)


@tool
def check_mountain_weather(destination: str, start_date: str, duration_days: int) -> str:
    """
    Retrieve a simulated multi-day mountain weather outlook for an
    Uttarakhand destination starting on the given date, including temperature
    ranges, precipitation risk, and wind conditions relevant to trek planning.
    """
    lines = [f"WEATHER OUTLOOK: {destination}, Uttarakhand starting {start_date} ({duration_days} days)"]
    for day in range(1, duration_days + 1):
        lines.append(
            f"Day {day}: Daytime {10 - day}°C / Night {-5 - day}°C, "
            f"precipitation chance {15 + (day % 4) * 10}%, "
            f"wind {10 + (day % 5) * 5} km/h. "
            f"{'Clear skies expected, good visibility of Himalayan peaks.' if day % 2 == 0 else 'Partial cloud cover, possible afternoon snow at altitude.'}"
        )
    lines.append(
        "Advisory: Mountain weather in Uttarakhand changes rapidly; carry layered insulation, "
        "a waterproof shell, and monitor local forecasts daily. Avoid trekking during peak "
        "monsoon (mid-Jul to Aug) due to landslide risk. Best seasons: May-Jun, Sep-Oct for "
        "most treks; Dec-Mar for snow treks."
    )
    lines.append(
        "Check weather: https://mausam.imd.gov.in | https://www.mountain-forecast.com"
    )
    return "\n".join(lines)


@tool
def generate_gear_and_budget(trek_difficulty: str, duration_days: int, budget: float) -> str:
    """
    Generate a recommended gear checklist and a cost breakdown (permits,
    guide/porter fees, food, lodging, gear rental) for an Uttarakhand trek
    that fits within the stated difficulty level, trip length, and total budget in INR.
    """
    per_day_estimates = {
        "easy": 1500,
        "moderate": 2500,
        "hard": 4000,
        "technical": 6500,
    }
    per_day = per_day_estimates.get(trek_difficulty.lower(), 2000)
    trek_cost = per_day * duration_days
    permit_cost = 600 if trek_difficulty.lower() in ("hard", "technical") else 150
    gear_rental = 2000 if trek_difficulty.lower() in ("hard", "technical") else 800
    transit_estimate = 2500  # average one-way

    total = trek_cost + permit_cost + gear_rental + transit_estimate

    lines = [
        f"GEAR & BUDGET BREAKDOWN ({trek_difficulty}, {duration_days} days, budget ₹{budget:.0f})",
        f"- Guide/porter + lodging + food: ₹{trek_cost:,.0f} (₹{per_day:,}/day)",
        f"- Forest/national park permits & eco fees: ₹{permit_cost:,.0f}",
        f"- Gear rental (trekking poles, crampons, gaiters, down jacket): ₹{gear_rental:,.0f}",
        f"- Estimated transit (one way): ₹{transit_estimate:,.0f}",
        f"- Estimated total: ₹{total:,.0f}",
        (
            "- Budget status: "
            + (
                "WITHIN BUDGET ✅"
                if total <= budget
                else f"OVER BUDGET by ₹{(total - budget):,.0f} ⚠️"
            )
        ),
        (
            "Essential gear checklist: layered insulation (fleece + down jacket), "
            "waterproof shell (rain jacket & pants), trekking poles, sturdy ankle-support "
            "boots, headlamp, water purification tablets/LifeStraw, basic first-aid kit, "
            "sunscreen SPF50+, sunglasses, sleeping bag (comfort -5°C to -10°C for high "
            "altitude), daypack 30-40L, thermal innerwear, woolen cap & gloves."
        ),
        "",
        "BOOKING & RENTAL LINKS:",
        "- Rent gear: https://www.gearcove.in | https://www.adventurenation.com/rental",
        "- Trek operators: https://www.indiahikes.com | https://www.bikatadventures.com | https://www.trekthehimalayas.com",
        "- Book stays/homestays: https://www.booking.com | https://www.airbnb.co.in",
        "- Forest permits (Uttarakhand): https://forest.uk.gov.in",
    ]
    return "\n".join(lines)


TOOLS = [get_basecamp_transit, analyze_trail_elevation, check_mountain_weather, generate_gear_and_budget]


# --------------------------------------------------------------------------
# Agent setup
# --------------------------------------------------------------------------

AGENT_SYSTEM_PROMPT = """You are YAM (Yet Another Mountaineer), an expert trekking and \
mountaineering itinerary planner specializing in Uttarakhand, India. Given a trip \
request, use the available tools to gather transit options, elevation/acclimatization \
data, weather outlook, and a gear/budget breakdown. Then synthesize ALL of that tool \
output into a detailed, day-by-day itinerary.

All costs MUST be in Indian Rupees (₹ / INR). Do NOT use USD.

You MUST call every tool at least once before producing your final answer.

Your final answer must be a single JSON object with EXACTLY this shape and no extra \
commentary, markdown fences, or prose outside the JSON:

{{
  "total_estimated_cost": <number in INR>,
  "timeline": [
    {{
      "day_number": <int>,
      "time": "<e.g. '06:00' or 'Morning'>",
      "title": "<short step title>",
      "description": "<what happens in this step, include any useful booking links from tool output>",
      "altitude_gain": "<e.g. '450m' or null>",
      "transport_mode": "<e.g. 'jeep', 'foot', 'flight', 'train', 'bus' or null>",
      "cost": <number in INR or null>
    }}
  ]
}}

Cover the transit day(s), each trek day (including rest/acclimatization days), and return \
a total_estimated_cost consistent with the budget breakdown tool's output. Include relevant \
booking links (IRCTC, bus, gear rental, trek operators) in the description where applicable.
"""

prompt = ChatPromptTemplate.from_messages([
    ("system", AGENT_SYSTEM_PROMPT),
    ("human", "{input}"),
    MessagesPlaceholder(variable_name="agent_scratchpad"),
])

agent = create_tool_calling_agent(llm, TOOLS, prompt)
agent_executor = AgentExecutor(
    agent=agent,
    tools=TOOLS,
    verbose=True,
    max_iterations=10,
    return_intermediate_steps=True,
    handle_parsing_errors=True,
    # If the loop ever hits max_iterations, force one more LLM call to
    # produce a real (JSON) final answer instead of returning a canned
    # "stopped due to iteration limit" string with no JSON in it.
    early_stopping_method="generate",
)


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


import re as _re


def _extract_json_block(text: str) -> dict:
    """Best-effort extraction of a JSON object from raw agent text output.

    Handles common LLM quirks: <think>…</think> wrapper, markdown fences,
    prose before/after the JSON, and nested braces.
    """
    if not text or not text.strip():
        raise ValueError("Empty agent output — no JSON to extract.")

    # 1. Strip <think>…</think> blocks (some reasoning models emit these)
    text = _re.sub(r"<think>.*?</think>", "", text, flags=_re.DOTALL).strip()

    # 2. Try to pull JSON from a markdown code fence first
    fence_match = _re.search(
        r"```(?:json)?\s*\n?(.*?)```", text, _re.DOTALL
    )
    if fence_match:
        text = fence_match.group(1).strip()

    # 3. Find the outermost { … } pair
    start = text.find("{")
    if start == -1:
        raise ValueError("No JSON object found in agent output.")

    # Walk forward to find the matching closing brace (handles nesting)
    depth = 0
    in_string = False
    escape_next = False
    end = -1
    for i in range(start, len(text)):
        ch = text[i]
        if escape_next:
            escape_next = False
            continue
        if ch == "\\":
            escape_next = True
            continue
        if ch == '"':
            in_string = not in_string
            continue
        if in_string:
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                end = i
                break

    if end == -1:
        # Fallback to simple rfind
        end = text.rfind("}")

    if end < start:
        raise ValueError("No JSON object found in agent output.")

    return json.loads(text[start : end + 1])


def _build_fallback_itinerary(request: "ItineraryRequest") -> dict:
    """Deterministically build a basic itinerary from the request parameters
    when the LLM completely fails to produce JSON.  This ensures the user
    always gets *something* back.  All costs in INR."""
    per_day = {"easy": 1500, "moderate": 2500, "hard": 4000, "technical": 6500}.get(
        request.trek_difficulty.lower(), 2000
    )
    trek_cost = per_day * request.duration_days
    permit = 600 if request.trek_difficulty.lower() in ("hard", "technical") else 150
    gear = 2000 if request.trek_difficulty.lower() in ("hard", "technical") else 800
    transit = 2500
    total = trek_cost + permit + gear + transit

    timeline = []
    # Day 1: transit
    timeline.append({
        "day_number": 1,
        "time": "Morning",
        "title": f"Travel from {request.origin} to {request.destination}",
        "description": (
            f"Depart {request.origin} and travel to {request.destination} trailhead "
            f"via bus/shared jeep. Arrive by evening, check in to lodge/homestay. "
            f"Book bus: https://utconline.uk.gov.in | Train: https://www.irctc.co.in"
        ),
        "altitude_gain": None,
        "transport_mode": "bus",
        "cost": transit,
    })
    # Trek days
    base_gain = {"easy": 300, "moderate": 550, "hard": 800, "technical": 1000}.get(
        request.trek_difficulty.lower(), 500
    )
    for day in range(2, request.duration_days):
        if (day - 1) % 3 == 0:
            timeline.append({
                "day_number": day,
                "time": "Morning",
                "title": "Acclimatization & rest day",
                "description": "Short exploratory hike around camp or nearby bugyal, rest and hydrate.",
                "altitude_gain": "0m",
                "transport_mode": "foot",
                "cost": per_day,
            })
        else:
            gain = base_gain + (day * 20)
            timeline.append({
                "day_number": day,
                "time": "06:00",
                "title": f"Trek day {day - 1}",
                "description": f"Ascend approx {gain}m along the trail. Stay hydrated, carry 3-4L water.",
                "altitude_gain": f"{gain}m",
                "transport_mode": "foot",
                "cost": per_day,
            })
    # Last day: return
    timeline.append({
        "day_number": request.duration_days,
        "time": "Morning",
        "title": f"Return to {request.origin}",
        "description": f"Descend and travel back to {request.origin} via shared jeep/bus.",
        "altitude_gain": None,
        "transport_mode": "jeep",
        "cost": transit,
    })

    return {"total_estimated_cost": total, "timeline": timeline}


SUMMARISE_PROMPT = """\
You are a JSON formatter for an Uttarakhand trek planning system. \
You will receive tool outputs. Combine them into a SINGLE JSON object — nothing \
else — with exactly this schema. All costs must be in Indian Rupees (INR).

{{
  "total_estimated_cost": <number in INR>,
  "timeline": [
    {{
      "day_number": <int>,
      "time": "<e.g. '06:00' or 'Morning'>",
      "title": "<short step title>",
      "description": "<what happens, include booking links where relevant>",
      "altitude_gain": "<e.g. '450m' or null>",
      "transport_mode": "<e.g. 'jeep','foot','flight','train','bus' or null>",
      "cost": <number in INR or null>
    }}
  ]
}}

Respond with ONLY the JSON — no markdown fences, no commentary.

TOOL OUTPUTS:
{tool_outputs}
"""


@app.post("/generate_itinerary", response_model=ItineraryResponse)
async def generate_itinerary(request: ItineraryRequest) -> ItineraryResponse:
    """
    Generate a full mountaineering/trekking itinerary by running the LangChain
    tool-calling agent over transit, elevation, weather, and budget tools,
    then parsing the agent's final JSON output into a structured
    ItineraryResponse.

    If the agent fails to produce valid JSON, we make one more focused LLM
    call with the collected tool outputs.  If that also fails, we fall back
    to a deterministic itinerary built from the request parameters.
    """
    user_input = (
        f"Plan a trek from {request.origin} to {request.destination} in Uttarakhand, "
        f"starting {request.start_date.isoformat()}, lasting {request.duration_days} days, "
        f"with a total budget of ₹{request.budget:.0f} INR, at "
        f"'{request.trek_difficulty}' difficulty level."
    )

    try:
        result = await agent_executor.ainvoke({"input": user_input})
        raw_output = result.get("output", "")
        intermediate_steps = result.get("intermediate_steps", [])

        print("\n" + "=" * 80)
        print("RAW AGENT OUTPUT:")
        print(repr(raw_output))
        print("=" * 80 + "\n")

        # --- Attempt 1: parse the agent's final answer directly ---
        try:
            parsed = _extract_json_block(raw_output)
            return ItineraryResponse(**parsed)
        except (ValueError, json.JSONDecodeError, KeyError) as first_err:
            print(f"[YAM] Direct parse failed: {first_err}")

        # --- Attempt 2: re-invoke LLM with just the tool results ---
        tool_texts = []
        for action, observation in intermediate_steps:
            tool_texts.append(
                f"[{action.tool}] {observation}"
            )

        if tool_texts:
            print("[YAM] Attempting fallback summarise call …")
            combined = "\n\n".join(tool_texts)
            summary_prompt = SUMMARISE_PROMPT.format(tool_outputs=combined)
            try:
                summary_response = await llm.ainvoke(summary_prompt)
                summary_text = (
                    summary_response.content
                    if hasattr(summary_response, "content")
                    else str(summary_response)
                )
                print("[YAM] Fallback LLM response:")
                print(repr(summary_text))
                parsed = _extract_json_block(summary_text)
                return ItineraryResponse(**parsed)
            except Exception as second_err:
                print(f"[YAM] Fallback summarise also failed: {second_err}")

        # --- Attempt 3: deterministic fallback ---
        print("[YAM] Using deterministic fallback itinerary.")
        fallback = _build_fallback_itinerary(request)
        return ItineraryResponse(**fallback)

    except Exception as exc:
        import traceback
        traceback.print_exc()
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