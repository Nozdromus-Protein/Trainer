import asyncio
import base64
import json
import os
import re
from typing import Optional, Dict, Any, List

from fastapi import FastAPI, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from google import genai
from google.genai import types
from openai import OpenAI
from pydantic import BaseModel


app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

AI_PROVIDER = os.environ.get("AI_PROVIDER", "gemini").strip().lower()

OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "").strip()
OPENAI_MODEL = os.environ.get("OPENAI_MODEL", "gpt-5.4-mini").strip()

GEMINI_API_KEYS = [
    key.strip()
    for key in os.environ.get("GEMINI_API_KEYS", os.environ.get("GEMINI_API_KEY", "")).split(",")
    if key.strip()
]

GEMINI_MODELS = [
    model.strip()
    for model in os.environ.get(
        "GEMINI_MODELS",
        os.environ.get("GEMINI_MODEL", "gemini-2.5-flash")
    ).split(",")
    if model.strip()
]

if not GEMINI_MODELS:
    GEMINI_MODELS = ["gemini-2.5-flash"]


class MealAnalysis(BaseModel):
    name: str
    calories: int
    protein: int
    carbs: int
    sugar: int
    fat: int
    saturated_fat: float
    fiber: float
    salt: float
    confidence: float
    note: Optional[str] = None


@app.get("/")
def home():
    return {
        "status": "Backend AI dziala - OpenAI/Gemini nutrition + Trainer AI v7",
        "default_provider": AI_PROVIDER,
        "openai_model": OPENAI_MODEL,
        "gemini_models": GEMINI_MODELS,
        "gemini_keys": len(GEMINI_API_KEYS),
        "openai_key": bool(OPENAI_API_KEY),
        "nutrition_endpoints": [
            "POST /analyze-meal",
        ],
        "trainer_endpoints": [
            "GET /trainer/health",
            "POST /analyze-workout",
            "POST /workout/analyze",
            "POST /generate-workout-plan",
            "POST /workout/generate-plan",
            "POST /analyze-exercise-form",
            "POST /workout/analyze-form",
            "POST /chat",
            "POST /ai/chat",
        ],
    }


def get_gemini_client(index: int):
    if not GEMINI_API_KEYS:
        raise RuntimeError("Brak GEMINI_API_KEYS albo GEMINI_API_KEY w Render Environment")
    return genai.Client(api_key=GEMINI_API_KEYS[index % len(GEMINI_API_KEYS)])


def get_openai_client():
    if not OPENAI_API_KEY:
        raise RuntimeError("Brak OPENAI_API_KEY w Render Environment")
    return OpenAI(api_key=OPENAI_API_KEY)


def clean_json_text(text: str) -> str:
    result = (text or "").strip()

    if result.startswith("```json"):
        result = result.replace("```json", "").replace("```", "").strip()
    elif result.startswith("```"):
        result = result.replace("```", "").strip()

    start = result.find("{")
    end = result.rfind("}")
    if start != -1 and end != -1 and end > start:
        result = result[start:end + 1]

    return result


def to_float(value, default=0.0):
    try:
        if value is None:
            return default

        if isinstance(value, str):
            text = value.lower().replace(",", ".").strip()
            match = re.search(r"-?\d+(?:\.\d+)?", text)
            if not match:
                return default
            return float(match.group(0))

        return float(value)
    except Exception:
        return default


def to_int(value, default=0):
    return int(round(to_float(value, default)))


MICRO_KEYS = [
    "Rozpuszczalne w tłuszczach / Witamina A [µg]",
    "Rozpuszczalne w tłuszczach / Witamina D [µg]",
    "Rozpuszczalne w tłuszczach / Witamina E [mg]",
    "Rozpuszczalne w tłuszczach / Witamina K [µg]",
    "Rozpuszczalne w wodzie / Witamina C [mg]",
    "Witaminy z grupy B / B1 Tiamina [mg]",
    "Witaminy z grupy B / B2 Ryboflawina [mg]",
    "Witaminy z grupy B / B3 Niacyna/PP [mg]",
    "Witaminy z grupy B / B5 Kwas pantotenowy [mg]",
    "Witaminy z grupy B / B6 Pirydoksyna [mg]",
    "Witaminy z grupy B / B7 Biotyna [µg]",
    "Witaminy z grupy B / B9 Kwas foliowy [µg]",
    "Witaminy z grupy B / B12 Kobalamina [µg]",
    "Makroelementy / Wapń [mg]",
    "Makroelementy / Fosfor [mg]",
    "Makroelementy / Magnez [mg]",
    "Makroelementy / Potas [mg]",
    "Makroelementy / Sód [mg]",
    "Makroelementy / Chlor [mg]",
    "Makroelementy / Siarka [mg]",
    "Mikroelementy / Żelazo [mg]",
    "Mikroelementy / Cynk [mg]",
    "Mikroelementy / Miedź [mg]",
    "Mikroelementy / Mangan [mg]",
    "Mikroelementy / Jod [µg]",
    "Mikroelementy / Selen [µg]",
    "Mikroelementy / Fluor [mg]",
    "Mikroelementy / Chrom [µg]",
    "Mikroelementy / Molibden [µg]",
]


def empty_micro_map() -> dict:
    return {key: 0 for key in MICRO_KEYS}


def normalize_micro_nutrients(raw_value) -> dict:
    micros = empty_micro_map()

    if isinstance(raw_value, dict):
        for key, value in raw_value.items():
            key_text = str(key).strip()
            number = to_float(value, 0)
            if key_text:
                micros[key_text] = number

    elif isinstance(raw_value, list):
        for item in raw_value:
            if isinstance(item, dict):
                name = str(item.get("name") or item.get("label") or item.get("key") or "").strip()
                unit = str(item.get("unit") or "").strip()
                value = to_float(item.get("value") or item.get("amount") or item.get("amount_per_100"), 0)
                if name:
                    final_key = name if not unit else f"{name} [{unit}]"
                    micros[final_key] = value

    return micros


def morele_micro_fallback() -> dict:
    micros = empty_micro_map()
    micros.update({
        "Rozpuszczalne w tłuszczach / Witamina A [µg]": 96,
        "Rozpuszczalne w tłuszczach / Witamina D [µg]": 0,
        "Rozpuszczalne w tłuszczach / Witamina E [mg]": 0.89,
        "Rozpuszczalne w tłuszczach / Witamina K [µg]": 3.3,
        "Rozpuszczalne w wodzie / Witamina C [mg]": 10,
        "Witaminy z grupy B / B1 Tiamina [mg]": 0.03,
        "Witaminy z grupy B / B2 Ryboflawina [mg]": 0.04,
        "Witaminy z grupy B / B3 Niacyna/PP [mg]": 0.6,
        "Witaminy z grupy B / B5 Kwas pantotenowy [mg]": 0.24,
        "Witaminy z grupy B / B6 Pirydoksyna [mg]": 0.05,
        "Witaminy z grupy B / B7 Biotyna [µg]": 0.3,
        "Witaminy z grupy B / B9 Kwas foliowy [µg]": 9,
        "Witaminy z grupy B / B12 Kobalamina [µg]": 0,
        "Makroelementy / Wapń [mg]": 13,
        "Makroelementy / Fosfor [mg]": 23,
        "Makroelementy / Magnez [mg]": 10,
        "Makroelementy / Potas [mg]": 259,
        "Makroelementy / Sód [mg]": 1,
        "Makroelementy / Chlor [mg]": 2,
        "Makroelementy / Siarka [mg]": 6,
        "Mikroelementy / Żelazo [mg]": 0.39,
        "Mikroelementy / Cynk [mg]": 0.2,
        "Mikroelementy / Miedź [mg]": 0.08,
        "Mikroelementy / Mangan [mg]": 0.08,
        "Mikroelementy / Jod [µg]": 1,
        "Mikroelementy / Selen [µg]": 0.1,
        "Mikroelementy / Fluor [mg]": 0.001,
        "Mikroelementy / Chrom [µg]": 1,
        "Mikroelementy / Molibden [µg]": 1,
    })
    return micros


def apply_extra_fallbacks(result_json: dict) -> dict:
    calories = to_int(result_json.get("calories"), 0)
    protein = to_int(result_json.get("protein"), 0)
    carbs = to_int(result_json.get("carbs"), 0)
    sugar = to_int(result_json.get("sugar"), 0)
    fat = to_int(result_json.get("fat"), 0)

    saturated_fat = to_float(result_json.get("saturated_fat") or result_json.get("saturatedFat"), 0)
    fiber = to_float(result_json.get("fiber"), 0)
    salt = to_float(result_json.get("salt"), 0)

    name_raw = str(result_json.get("name", "Posiłek"))
    name = name_raw.lower()
    note = str(result_json.get("note", ""))

    raw_micros = (
        result_json.get("microNutrients")
        or result_json.get("micro_nutrients")
        or result_json.get("micronutrients")
        or result_json.get("vitaminsAndMinerals")
        or result_json.get("vitamins_minerals")
        or {}
    )

    micro_nutrients = normalize_micro_nutrients(raw_micros)

    if ("morele" in name or "morela" in name or "apricot" in name) and all(to_float(v, 0) == 0 for v in micro_nutrients.values()):
        micro_nutrients = morele_micro_fallback()

    additives = (
        result_json.get("additives")
        or result_json.get("emulsifiers")
        or result_json.get("emulgatory")
        or []
    )

    if not isinstance(additives, list):
        additives = []

    if saturated_fat <= 0 and fat > 0:
        if any(word in name for word in ["ser", "pizza", "burger", "mięso", "mieso", "sos", "makaron", "lasagne", "zapiekanka"]):
            saturated_fat = round(fat * 0.30, 1)
        else:
            saturated_fat = round(fat * 0.20, 1)

    if fiber <= 0 and carbs > 15:
        if any(word in name for word in ["makaron", "pieczywo", "chleb", "płatki", "platki", "owsianka", "warzywa", "ryż", "ryz", "morele", "morela"]):
            fiber = round(carbs * 0.07, 1)
        else:
            fiber = round(carbs * 0.04, 1)

    if salt <= 0:
        if any(word in name for word in ["pizza", "burger", "frytki", "kanapka", "makaron", "sos", "gotowe", "lasagne", "zapiekanka", "ser"]):
            salt = 1.5 if calories > 600 else 1.0
        elif calories > 400:
            salt = 0.8
        elif calories > 150:
            salt = 0.3
        else:
            salt = 0.1

    if note:
        note = note + " Dodatkowe wartości mogły zostać oszacowane, jeśli nie były widoczne na etykiecie."
    else:
        note = "Dodatkowe wartości mogły zostać oszacowane, jeśli nie były widoczne na etykiecie."

    return {
        "name": name_raw,
        "calories": calories,
        "protein": protein,
        "carbs": carbs,
        "sugar": sugar,
        "fat": fat,
        "saturated_fat": float(saturated_fat),
        "fiber": float(fiber),
        "salt": float(salt),
        "confidence": float(to_float(result_json.get("confidence"), 0.8)),
        "note": note,
        "microNutrients": micro_nutrients,
        "additives": additives,
    }


def build_prompt(description: str) -> str:
    return f"""
Przeanalizuj zdjęcie posiłku, produktu albo opakowania i oszacuj wartości odżywcze.

Dodatkowy opis od użytkownika:
"{description}"

Zwróć WYŁĄCZNIE poprawny JSON, bez markdown, bez ```json, bez komentarzy.

Format:
{{
  "name": "nazwa posiłku lub produktu po polsku",
  "calories": liczba_kcal,
  "protein": liczba_gramow_bialka,
  "carbs": liczba_gramow_weglowodanow,
  "sugar": liczba_gramow_cukru,
  "fat": liczba_gramow_tluszczu,
  "saturated_fat": liczba_gramow_tluszczow_nasyconych,
  "fiber": liczba_gramow_blonnika,
  "salt": liczba_gramow_soli,
  "confidence": liczba_od_0_do_1,
  "note": "krótka uwaga po polsku",
  "microNutrients": {{
    "Rozpuszczalne w tłuszczach / Witamina A [µg]": liczba,
    "Rozpuszczalne w tłuszczach / Witamina D [µg]": liczba,
    "Rozpuszczalne w tłuszczach / Witamina E [mg]": liczba,
    "Rozpuszczalne w tłuszczach / Witamina K [µg]": liczba,
    "Rozpuszczalne w wodzie / Witamina C [mg]": liczba,
    "Witaminy z grupy B / B1 Tiamina [mg]": liczba,
    "Witaminy z grupy B / B2 Ryboflawina [mg]": liczba,
    "Witaminy z grupy B / B3 Niacyna/PP [mg]": liczba,
    "Witaminy z grupy B / B5 Kwas pantotenowy [mg]": liczba,
    "Witaminy z grupy B / B6 Pirydoksyna [mg]": liczba,
    "Witaminy z grupy B / B7 Biotyna [µg]": liczba,
    "Witaminy z grupy B / B9 Kwas foliowy [µg]": liczba,
    "Witaminy z grupy B / B12 Kobalamina [µg]": liczba,
    "Makroelementy / Wapń [mg]": liczba,
    "Makroelementy / Fosfor [mg]": liczba,
    "Makroelementy / Magnez [mg]": liczba,
    "Makroelementy / Potas [mg]": liczba,
    "Makroelementy / Sód [mg]": liczba,
    "Makroelementy / Chlor [mg]": liczba,
    "Makroelementy / Siarka [mg]": liczba,
    "Mikroelementy / Żelazo [mg]": liczba,
    "Mikroelementy / Cynk [mg]": liczba,
    "Mikroelementy / Miedź [mg]": liczba,
    "Mikroelementy / Mangan [mg]": liczba,
    "Mikroelementy / Jod [µg]": liczba,
    "Mikroelementy / Selen [µg]": liczba,
    "Mikroelementy / Fluor [mg]": liczba,
    "Mikroelementy / Chrom [µg]": liczba,
    "Mikroelementy / Molibden [µg]": liczba
  }},
  "additives": [
    {{
      "name": "nazwa dodatku",
      "code": "E471",
      "category": "Emulgator / dodatek",
      "riskLevel": 2,
      "note": "krótki opis"
    }}
  ]
}}

Bardzo ważne:
- Analizuj tylko posiłek, produkt albo opakowanie jako całość.
- Nie zwracaj listy ingredients.
- Nie rozbijaj posiłku na składniki, chyba że użytkownik wyraźnie opisze porcję i trzeba oszacować całość.
- Jeśli widzisz tabelę wartości odżywczych, użyj jej jako głównego źródła.
- Jeśli użytkownik podał ilość porcji, przelicz wartości na zjedzoną ilość.
- Jeśli użytkownik pyta o składnik na 100 g, zwróć wartości na 100 g.
- Jeśli nie widzisz tabeli, oszacuj wszystkie wartości, także saturated_fat, fiber, salt oraz microNutrients.
- Nie zwracaj pustego microNutrients dla owoców, warzyw, mięsa, nabiału, pieczywa, pizzy, gotowych dań i produktów.
- Dla Morele / Morela / Apricot koniecznie zwróć witaminy i minerały typowe dla świeżych moreli na 100 g.
- Jeżeli dany produkt realnie nie ma konkretnej witaminy/minerału, wpisz 0.
- Sól podawaj jako gramy soli, nie jako sód.
- Cukier oznacza "w tym cukry".
- Tłuszcze nasycone oznaczają "w tym kwasy tłuszczowe nasycone".
"""


def get_mime_type(image_bytes: bytes) -> str:
    mime_type = "image/jpeg"

    if image_bytes.startswith(b"\x89PNG"):
        mime_type = "image/png"
    elif image_bytes.startswith(b"\xff\xd8\xff"):
        mime_type = "image/jpeg"
    elif image_bytes.startswith(b"RIFF") and b"WEBP" in image_bytes[:20]:
        mime_type = "image/webp"

    return mime_type


async def analyze_with_openai(prompt: str, image_bytes: bytes, mime_type: str) -> dict:
    client = get_openai_client()

    image_base64 = base64.b64encode(image_bytes).decode("utf-8")
    image_url = f"data:{mime_type};base64,{image_base64}"

    response = client.responses.create(
        model=OPENAI_MODEL,
        input=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": prompt,
                    },
                    {
                        "type": "input_image",
                        "image_url": image_url,
                    },
                ],
            }
        ],
        max_output_tokens=5000,
    )

    result_text = getattr(response, "output_text", "") or ""

    if not result_text:
        try:
            chunks = []
            for item in response.output:
                for content in item.content:
                    if hasattr(content, "text"):
                        chunks.append(content.text)
            result_text = "\n".join(chunks)
        except Exception:
            result_text = ""

    result_text = clean_json_text(result_text)
    print("ODPOWIEDZ OPENAI:", result_text)

    result_json = json.loads(result_text)
    final_result = apply_extra_fallbacks(result_json)
    final_result["aiProvider"] = "openai"
    final_result["aiModel"] = OPENAI_MODEL

    print("FINALNY WYNIK OPENAI:", final_result)
    return final_result


async def analyze_with_gemini(prompt: str, image_bytes: bytes, mime_type: str) -> dict:
    image_part = types.Part.from_bytes(
        data=image_bytes,
        mime_type=mime_type,
    )

    last_error = None

    for model_name in GEMINI_MODELS:
        model_unavailable = False

        for index in range(len(GEMINI_API_KEYS)):
            try:
                current_client = get_gemini_client(index)

                response = current_client.models.generate_content(
                    model=model_name,
                    contents=[
                        prompt,
                        image_part,
                    ],
                )

                result_text = clean_json_text(response.text or "")
                print(f"ODPOWIEDZ GEMINI MODEL {model_name} KLUCZ {index + 1}:", result_text)

                result_json = json.loads(result_text)
                final_result = apply_extra_fallbacks(result_json)
                final_result["aiProvider"] = "gemini"
                final_result["aiModel"] = model_name

                print("FINALNY WYNIK GEMINI:", final_result)

                return final_result

            except Exception as error:
                error_text = str(error)
                error_lower = error_text.lower()
                last_error = error_text

                print(f"BLAD GEMINI MODEL {model_name} KLUCZ {index + 1}:", error_text)

                is_503 = (
                    "503" in error_text
                    or "unavailable" in error_lower
                    or "high demand" in error_lower
                    or "overloaded" in error_lower
                    or "try again later" in error_lower
                )

                is_429 = (
                    "429" in error_text
                    or "quota" in error_lower
                    or "rate" in error_lower
                    or "resource_exhausted" in error_lower
                )

                if is_503:
                    print(f"MODEL {model_name} jest przeciążony. Przełączam na kolejny model.")
                    model_unavailable = True
                    await asyncio.sleep(1.2)
                    break

                if is_429:
                    print(f"KLUCZ {index + 1} ma limit/quota. Próba kolejnego klucza.")
                    continue

                raise RuntimeError(error_text)

        if model_unavailable:
            continue

    raise RuntimeError(f"Wszystkie modele/klucze Gemini zwróciły błąd. Ostatni błąd: {last_error}")


def error_result(name: str, error_text: str, note: str) -> dict:
    return {
        "error": error_text,
        "name": name,
        "calories": 0,
        "protein": 0,
        "carbs": 0,
        "sugar": 0,
        "fat": 0,
        "saturated_fat": 0,
        "fiber": 0,
        "salt": 0,
        "confidence": 0,
        "note": note,
        "microNutrients": empty_micro_map(),
        "additives": [],
    }





# ============================================================
# TRAINER APP - tekstowe endpointy AI do aplikacji "Trainer"
# ============================================================

class AnalyzeWorkoutRequest(BaseModel):
    # Opis jest OPCJONALNY — starsze wersje aplikacji (i klient wysyłający sam
    # ustrukturyzowany trening) nie przysyłały tego pola i dostawały HTTP 422
    # ("Field required", loc: body.description). Gdy opisu brak, budujemy go
    # z danych sesji/ćwiczeń w build_workout_analysis_prompt.
    description: Optional[str] = None
    # Ustrukturyzowany trening z aplikacji Trainer (podsumowanie sesji, wykonane
    # ćwiczenia i kontekst ostatnich dni). Wcześniej te pola były odrzucane jako
    # nieznane, więc analiza traciła najlepsze dane, jakie miała.
    session: Optional[Dict[str, Any]] = None
    exercises: Optional[List[Dict[str, Any]]] = None
    recent_history: Optional[List[Dict[str, Any]]] = None
    user: Optional[Dict[str, Any]] = None
    date: Optional[str] = None
    ai_provider: Optional[str] = None
    provider: Optional[str] = None

    def effective_description(self) -> str:
        """Opis treningu do promptu: jawny z klienta albo złożony z danych sesji."""
        text = (self.description or "").strip()
        if text:
            return text
        return build_description_from_session(self.session, self.exercises)


def build_description_from_session(
    session: Optional[Dict[str, Any]],
    exercises: Optional[List[Dict[str, Any]]],
) -> str:
    """Składa czytelny opis treningu z ustrukturyzowanych danych sesji.

    Używane, gdy klient nie przysłał pola `description` (zgodność wsteczna).
    """
    session = session or {}
    lines: List[str] = []

    name = str(session.get("name") or "").strip()
    lines.append(f"Trening: {name}." if name else "Trening.")

    stats: List[str] = []
    if session.get("duration_minutes") is not None:
        stats.append(f"czas {to_int(session.get('duration_minutes'), 0)} min")
    if session.get("exercise_count") is not None:
        stats.append(f"ćwiczeń: {to_int(session.get('exercise_count'), 0)}")
    if session.get("set_count") is not None:
        stats.append(f"serii: {to_int(session.get('set_count'), 0)}")
    if session.get("volume_kg") is not None:
        stats.append(f"objętość: {round(to_float(session.get('volume_kg'), 0))} kg")
    average_rpe = to_float(session.get("average_rpe"), 0)
    if average_rpe > 0:
        stats.append(f"średnie RPE {average_rpe:.1f}")
    if stats:
        lines.append(", ".join(stats).capitalize() + ".")

    for item in exercises or []:
        if not isinstance(item, dict):
            continue
        label = str(item.get("name") or item.get("exercise_id") or "Ćwiczenie").strip()
        parts: List[str] = []
        sets = to_int(item.get("sets"), 0)
        if sets > 0:
            parts.append(f"{sets} serie")
        reps = to_int(item.get("reps"), 0)
        if reps > 0:
            parts.append(f"{reps} powt.")
        weight = to_float(item.get("weight_kg"), 0)
        if weight > 0:
            parts.append(f"{weight:g} kg")
        duration = to_int(item.get("duration_sec"), 0)
        if duration > 0:
            parts.append(f"{duration} s")
        if parts:
            lines.append(f"- {label}: {' × '.join(parts)}")

    text = "\n".join(lines).strip()
    return text if text else "Trening bez dodatkowego opisu."


class GenerateWorkoutPlanRequest(BaseModel):
    goal: str
    days_per_week: int = 4
    equipment: str = ""
    limitations: str = ""
    level: str = "średniozaawansowany"
    user: Optional[Dict[str, Any]] = None
    ai_provider: Optional[str] = None
    provider: Optional[str] = None


class AnalyzeExerciseFormRequest(BaseModel):
    exercise: str
    notes: str = ""
    user: Optional[Dict[str, Any]] = None
    ai_provider: Optional[str] = None
    provider: Optional[str] = None


def to_str_list(value, default=None) -> List[str]:
    if default is None:
        default = []
    if value is None:
        return list(default)
    if isinstance(value, list):
        return [str(x).strip() for x in value if str(x).strip()]
    if isinstance(value, str):
        parts = [x.strip() for x in re.split(r"[,;\n]+", value) if x.strip()]
        return parts if parts else list(default)
    return list(default)


def normalize_weekday(value, default=1) -> int:
    if isinstance(value, (int, float)):
        day = int(value)
        return min(7, max(1, day))

    text = str(value or "").lower().strip()
    if "wt" in text or "tue" in text:
        return 2
    if "ś" in text or "sr" in text or "wed" in text:
        return 3
    if "czw" in text or "thu" in text:
        return 4
    if "pt" in text or "fri" in text:
        return 5
    if "sob" in text or "sat" in text:
        return 6
    if "niedz" in text or "sun" in text:
        return 7
    if "pon" in text or "mon" in text:
        return 1
    return default


def clamp_int(value, default=0, minimum=0, maximum=9999) -> int:
    number = to_int(value, default)
    return min(maximum, max(minimum, number))


def clamp_float(value, default=0.0, minimum=0.0, maximum=9999.0) -> float:
    number = to_float(value, default)
    return min(maximum, max(minimum, number))


def trainer_error_result(kind: str, error_text: str) -> dict:
    return {
        "error": error_text,
        "kind": kind,
        "summary": "Backend złapał błąd podczas obsługi Trainer AI.",
        "confidence": 0,
        "aiProvider": None,
        "aiModel": None,
    }


def build_workout_analysis_prompt(req: AnalyzeWorkoutRequest) -> str:
    # Sekcja z twardymi danymi z aplikacji — gdy klient je przysłał, są
    # dokładniejsze niż sam opis tekstowy (serie, ciężary, czasy, typ wpisu).
    structured_section = ""
    if req.session or req.exercises:
        structured_section = f"""
Dane sesji z aplikacji (źródło prawdy — używaj ich zamiast zgadywania):
{json.dumps(req.session or {}, ensure_ascii=False)}

Wykonane ćwiczenia (duration_sec dotyczy CZASU DANEGO ĆWICZENIA, nie całej sesji;
dla ćwiczeń powtórzeniowych może wynosić 0):
{json.dumps(req.exercises or [], ensure_ascii=False)}

Ostatnie treningi (kontekst):
{json.dumps(req.recent_history or [], ensure_ascii=False)}
"""

    return f"""
Jesteś trenerem personalnym, ale odpowiadasz praktycznie, bez lania wody.
Analizujesz opis treningu użytkownika aplikacji Trainer.

Opis treningu:
"{req.effective_description()}"

Data:
{req.date}

Profil użytkownika:
{json.dumps(req.user or {}, ensure_ascii=False)}
{structured_section}
Zwróć WYŁĄCZNIE poprawny JSON, bez markdown i bez komentarzy.

Format:
{{
  "summary": "krótkie podsumowanie treningu po polsku",
  "estimated_calories": liczba_kcal,
  "training_type": "siłowy/kardio/mieszany/mobilność",
  "intensity": "niska/średnia/wysoka",
  "duration_min": liczba_minut,
  "total_sets": liczba_serii,
  "total_reps": liczba_powtorzen,
  "estimated_volume_kg": liczba,
  "worked_muscles": ["partia 1", "partia 2"],
  "detected_exercises": [
    {{
      "name": "nazwa ćwiczenia po polsku",
      "sets": liczba,
      "reps": liczba,
      "weight_kg": liczba,
      "duration_sec": liczba,
      "muscles": ["partie"],
      "estimated_calories": liczba
    }}
  ],
  "suggestions": ["konkretna sugestia 1", "konkretna sugestia 2"],
  "recovery_advice": "rada regeneracyjna po polsku",
  "next_training_hint": "co zrobić następnym razem",
  "confidence": liczba_od_0_do_1
}}

Zasady:
- Jeśli opis jest niepełny, oszacuj rozsądnie, ale zaznacz to w summary albo suggestions.
- Nie diagnozuj medycznie.
- Jeżeli użytkownik wspomina ból, daj ostrożną uwagę i zasugeruj przerwanie ćwiczenia, zmniejszenie obciążenia albo konsultację ze specjalistą.
- Dla ćwiczeń siłowych licz objętość jako serie * powtórzenia * ciężar.
- Jeśli ciężar nie jest podany, użyj 0 w estimated_volume_kg, ale nadal analizuj trening.
"""


def build_workout_plan_prompt(req: GenerateWorkoutPlanRequest) -> str:
    days = min(7, max(1, int(req.days_per_week or 4)))
    return f"""
Jesteś trenerem personalnym i układasz plan treningowy do aplikacji Trainer.
Plan ma być konkretny, logiczny i dopasowany do poziomu użytkownika.

Cel:
"{req.goal}"

Poziom:
"{req.level}"

Dni treningowe w tygodniu:
{days}

Dostępny sprzęt:
"{req.equipment}"

Ograniczenia, kontuzje, uwagi:
"{req.limitations}"

Profil użytkownika:
{json.dumps(req.user or {}, ensure_ascii=False)}

Zwróć WYŁĄCZNIE poprawny JSON, bez markdown i bez komentarzy.

Format:
{{
  "name": "nazwa planu po polsku",
  "level": "początkujący/średniozaawansowany/zaawansowany",
  "goal": "cel planu",
  "note": "krótka notatka o założeniach",
  "days": [
    {{
      "weekday": 1,
      "title": "nazwa dnia treningowego",
      "focus": "główna partia/cel dnia",
      "items": [
        {{
          "exercise": "nazwa ćwiczenia po polsku",
          "sets": liczba,
          "reps": liczba,
          "duration_sec": liczba,
          "rest_sec": liczba,
          "tempo": "np. 3-1-1 albo spokojne",
          "note": "krótka wskazówka"
        }}
      ]
    }}
  ],
  "warmup": ["element rozgrzewki 1", "element rozgrzewki 2"],
  "cooldown": ["element wyciszenia 1", "element wyciszenia 2"],
  "progression": "jak progresować z tygodnia na tydzień",
  "warnings": ["ważne uwagi bezpieczeństwa"],
  "confidence": liczba_od_0_do_1
}}

Zasady:
- Uwzględnij dokładnie {days} dni treningowych.
- weekday podawaj jako liczby 1-7, gdzie 1 to poniedziałek.
- Dla początkującego dawaj prostsze ćwiczenia, więcej kontroli techniki i mniejszą objętość.
- Dla średniozaawansowanego dawaj normalną progresję siłową i akcesoria.
- Dla zaawansowanego dawaj większą objętość, trudniejsze warianty i bardziej świadomą progresję.
- Nie dawaj ćwiczeń sprzecznych z ograniczeniami.
- Jeżeli sprzęt jest ograniczony, używaj ćwiczeń z masą ciała, gumami, hantlami albo domowych zamienników.
"""


def build_exercise_form_prompt(req: AnalyzeExerciseFormRequest) -> str:
    return f"""
Jesteś trenerem personalnym i analizujesz technikę ćwiczenia na podstawie opisu użytkownika.
Nie widzisz filmu, więc oceniasz tylko to, co użytkownik napisał.

Ćwiczenie:
"{req.exercise}"

Opis użytkownika:
"{req.notes}"

Profil użytkownika:
{json.dumps(req.user or {}, ensure_ascii=False)}

Zwróć WYŁĄCZNIE poprawny JSON, bez markdown i bez komentarzy.

Format:
{{
  "exercise": "nazwa ćwiczenia",
  "form_score": liczba_od_0_do_100,
  "summary": "krótkie podsumowanie po polsku",
  "likely_issues": ["możliwy błąd 1", "możliwy błąd 2"],
  "corrections": ["konkretna poprawka 1", "konkretna poprawka 2"],
  "safety_notes": ["uwaga bezpieczeństwa 1"],
  "beginner_version": "łatwiejsza wersja ćwiczenia",
  "advanced_version": "trudniejsza wersja ćwiczenia",
  "when_to_stop": "kiedy przerwać ćwiczenie",
  "confidence": liczba_od_0_do_1
}}

Zasady:
- Nie stawiaj diagnoz medycznych.
- Jeżeli użytkownik wspomina o ostrym bólu, promieniowaniu, drętwieniu albo zawrotach, zalecaj przerwanie ćwiczenia i konsultację.
- Dawaj krótkie, praktyczne wskazówki, które można od razu sprawdzić podczas treningu.
"""


def normalize_workout_analysis_result(raw: dict) -> dict:
    detected = raw.get("detected_exercises") or raw.get("exercises") or []
    if not isinstance(detected, list):
        detected = []

    normalized_exercises = []
    for item in detected:
        if not isinstance(item, dict):
            continue
        normalized_exercises.append({
            "name": str(item.get("name") or item.get("exercise") or "Ćwiczenie"),
            "sets": clamp_int(item.get("sets"), 0, 0, 100),
            "reps": clamp_int(item.get("reps"), 0, 0, 10000),
            "weight_kg": clamp_float(item.get("weight_kg") or item.get("weightKg"), 0, 0, 1000),
            "duration_sec": clamp_int(item.get("duration_sec") or item.get("durationSec"), 0, 0, 86400),
            "muscles": to_str_list(item.get("muscles"), []),
            "estimated_calories": clamp_int(item.get("estimated_calories") or item.get("calories"), 0, 0, 5000),
        })

    return {
        "summary": str(raw.get("summary") or raw.get("note") or "Analiza treningu gotowa."),
        "estimated_calories": clamp_int(raw.get("estimated_calories") or raw.get("calories"), 0, 0, 5000),
        "training_type": str(raw.get("training_type") or raw.get("type") or "mieszany"),
        "intensity": str(raw.get("intensity") or "średnia"),
        "duration_min": clamp_int(raw.get("duration_min") or raw.get("duration"), 0, 0, 1440),
        "total_sets": clamp_int(raw.get("total_sets"), 0, 0, 500),
        "total_reps": clamp_int(raw.get("total_reps"), 0, 0, 10000),
        "estimated_volume_kg": clamp_float(raw.get("estimated_volume_kg") or raw.get("volume"), 0, 0, 1000000),
        "worked_muscles": to_str_list(raw.get("worked_muscles") or raw.get("muscles"), []),
        "detected_exercises": normalized_exercises,
        "suggestions": to_str_list(raw.get("suggestions"), ["Zapisz ciężar, serie i powtórzenia, żeby aplikacja mogła lepiej śledzić progres."]),
        "recovery_advice": str(raw.get("recovery_advice") or "Zadbaj o sen, nawodnienie i lekką mobilizację po treningu."),
        "next_training_hint": str(raw.get("next_training_hint") or "Na kolejnym treningu spróbuj utrzymać technikę i dodać mały progres, jeśli czujesz zapas."),
        "confidence": clamp_float(raw.get("confidence"), 0.75, 0, 1),
    }


def normalize_workout_plan_result(raw: dict, req: GenerateWorkoutPlanRequest) -> dict:
    raw_days = raw.get("days") or raw.get("week_plan") or raw.get("plan") or []
    if not isinstance(raw_days, list):
        raw_days = []

    normalized_days = []
    for i, day in enumerate(raw_days):
        if not isinstance(day, dict):
            continue

        raw_items = day.get("items") or day.get("exercises") or []
        if not isinstance(raw_items, list):
            raw_items = []

        items = []
        for item in raw_items:
            if not isinstance(item, dict):
                continue
            items.append({
                "exercise": str(item.get("exercise") or item.get("name") or "Ćwiczenie"),
                "sets": clamp_int(item.get("sets"), 3, 0, 50),
                "reps": clamp_int(item.get("reps"), 10, 0, 500),
                "duration_sec": clamp_int(item.get("duration_sec") or item.get("durationSec"), 0, 0, 7200),
                "rest_sec": clamp_int(item.get("rest_sec") or item.get("restSec"), 90, 0, 1800),
                "tempo": str(item.get("tempo") or "kontrolowane"),
                "note": str(item.get("note") or item.get("reason") or ""),
            })

        normalized_days.append({
            "weekday": normalize_weekday(day.get("weekday") or day.get("day"), (i % 7) + 1),
            "title": str(day.get("title") or "Trening"),
            "focus": str(day.get("focus") or ""),
            "items": items,
        })

    if not normalized_days:
        fallback_items = [
            {"exercise": "Przysiad", "sets": 3, "reps": 10, "duration_sec": 0, "rest_sec": 90, "tempo": "kontrolowane", "note": "Pilnuj kolan i napięcia brzucha."},
            {"exercise": "Pompka", "sets": 3, "reps": 8, "duration_sec": 0, "rest_sec": 90, "tempo": "kontrolowane", "note": "W razie potrzeby rób na kolanach."},
            {"exercise": "Deska", "sets": 3, "reps": 0, "duration_sec": 30, "rest_sec": 60, "tempo": "stabilnie", "note": "Nie zapadaj się w lędźwiach."},
        ]
        for i in range(min(7, max(1, req.days_per_week))):
            normalized_days.append({
                "weekday": i + 1,
                "title": "Plan bazowy",
                "focus": "całe ciało",
                "items": fallback_items,
            })

    return {
        "name": str(raw.get("name") or f"Plan Trainer: {req.goal}"),
        "level": str(raw.get("level") or req.level),
        "goal": str(raw.get("goal") or req.goal),
        "note": str(raw.get("note") or "Plan wygenerowany przez backend AI Trainer."),
        "days": normalized_days,
        "warmup": to_str_list(raw.get("warmup"), ["5-8 minut lekkiego cardio", "mobilizacja bioder, barków i kręgosłupa"]),
        "cooldown": to_str_list(raw.get("cooldown"), ["spokojny oddech", "lekkie rozciąganie trenowanych partii"]),
        "progression": str(raw.get("progression") or "Co tydzień dodaj 1-2 powtórzenia albo mały ciężar, jeśli technika zostaje dobra."),
        "warnings": to_str_list(raw.get("warnings"), ["Nie ćwicz przez ostry ból. Technika ma pierwszeństwo przed ciężarem."]),
        "confidence": clamp_float(raw.get("confidence"), 0.75, 0, 1),
    }


def normalize_exercise_form_result(raw: dict, req: AnalyzeExerciseFormRequest) -> dict:
    return {
        "exercise": str(raw.get("exercise") or req.exercise),
        "form_score": clamp_int(raw.get("form_score") or raw.get("score"), 70, 0, 100),
        "summary": str(raw.get("summary") or "Ocena techniki została przygotowana na podstawie opisu."),
        "likely_issues": to_str_list(raw.get("likely_issues") or raw.get("issues"), []),
        "corrections": to_str_list(raw.get("corrections"), ["Nagraj serię z boku i z przodu, żeby łatwiej ocenić ustawienie ciała."]),
        "safety_notes": to_str_list(raw.get("safety_notes"), ["Przerwij ćwiczenie, jeśli pojawia się ostry ból albo drętwienie."]),
        "beginner_version": str(raw.get("beginner_version") or "Wybierz lżejszą wersję z mniejszym zakresem ruchu i spokojnym tempem."),
        "advanced_version": str(raw.get("advanced_version") or "Dodaj większą kontrolę tempa, obciążenie albo trudniejszy wariant dopiero po opanowaniu techniki."),
        "when_to_stop": str(raw.get("when_to_stop") or "Przerwij, jeśli tracisz kontrolę pozycji albo pojawia się ból."),
        "confidence": clamp_float(raw.get("confidence"), 0.7, 0, 1),
    }


async def generate_text_json_with_openai(prompt: str, max_output_tokens: int = 7000) -> dict:
    client = get_openai_client()

    response = client.responses.create(
        model=OPENAI_MODEL,
        input=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": prompt,
                    }
                ],
            }
        ],
        max_output_tokens=max_output_tokens,
    )

    result_text = getattr(response, "output_text", "") or ""

    if not result_text:
        try:
            chunks = []
            for item in response.output:
                for content in item.content:
                    if hasattr(content, "text"):
                        chunks.append(content.text)
            result_text = "\n".join(chunks)
        except Exception:
            result_text = ""

    result_text = clean_json_text(result_text)
    print("ODPOWIEDZ OPENAI TRAINER:", result_text)

    result_json = json.loads(result_text)
    result_json["aiProvider"] = "openai"
    result_json["aiModel"] = OPENAI_MODEL
    return result_json


async def generate_text_json_with_gemini(prompt: str) -> dict:
    last_error = None

    for model_name in GEMINI_MODELS:
        model_unavailable = False

        for index in range(len(GEMINI_API_KEYS)):
            try:
                current_client = get_gemini_client(index)

                response = current_client.models.generate_content(
                    model=model_name,
                    contents=[prompt],
                )

                result_text = clean_json_text(response.text or "")
                print(f"ODPOWIEDZ GEMINI TRAINER MODEL {model_name} KLUCZ {index + 1}:", result_text)

                result_json = json.loads(result_text)
                result_json["aiProvider"] = "gemini"
                result_json["aiModel"] = model_name
                return result_json

            except Exception as error:
                error_text = str(error)
                error_lower = error_text.lower()
                last_error = error_text

                print(f"BLAD GEMINI TRAINER MODEL {model_name} KLUCZ {index + 1}:", error_text)

                is_503 = (
                    "503" in error_text
                    or "unavailable" in error_lower
                    or "high demand" in error_lower
                    or "overloaded" in error_lower
                    or "try again later" in error_lower
                )

                is_429 = (
                    "429" in error_text
                    or "quota" in error_lower
                    or "rate" in error_lower
                    or "resource_exhausted" in error_lower
                )

                if is_503:
                    print(f"MODEL {model_name} jest przeciążony. Przełączam na kolejny model.")
                    model_unavailable = True
                    await asyncio.sleep(1.2)
                    break

                if is_429:
                    print(f"KLUCZ {index + 1} ma limit/quota. Próba kolejnego klucza.")
                    continue

                raise RuntimeError(error_text)

        if model_unavailable:
            continue

    raise RuntimeError(f"Wszystkie modele/klucze Gemini zwróciły błąd w Trainer. Ostatni błąd: {last_error}")


async def generate_text_json(prompt: str, selected_provider: Optional[str] = None) -> dict:
    provider = (selected_provider or AI_PROVIDER).strip().lower()

    if provider in ["openai", "gpt"]:
        return await generate_text_json_with_openai(prompt)

    if provider == "gemini":
        return await generate_text_json_with_gemini(prompt)

    if provider == "openai_then_gemini":
        try:
            return await generate_text_json_with_openai(prompt)
        except Exception as openai_error:
            print("OPENAI TRAINER PADLO, PROBUJE GEMINI:", openai_error)
            return await generate_text_json_with_gemini(prompt)

    if provider == "gemini_then_openai":
        try:
            return await generate_text_json_with_gemini(prompt)
        except Exception as gemini_error:
            print("GEMINI TRAINER PADLO, PROBUJE OPENAI:", gemini_error)
            return await generate_text_json_with_openai(prompt)

    raise RuntimeError(f"Nieznany provider AI: {provider}. Ustaw openai, gpt, gemini, openai_then_gemini albo gemini_then_openai.")


@app.get("/trainer/health")
def trainer_health():
    return {
        "status": "Trainer AI endpoints ready",
        "default_provider": AI_PROVIDER,
        "openai_model": OPENAI_MODEL,
        "gemini_models": GEMINI_MODELS,
        "gemini_keys": len(GEMINI_API_KEYS),
        "openai_key": bool(OPENAI_API_KEY),
    }


@app.post("/analyze-workout")
@app.post("/workout/analyze")
async def analyze_workout(req: AnalyzeWorkoutRequest):
    try:
        prompt = build_workout_analysis_prompt(req)
        raw = await generate_text_json(prompt, req.ai_provider or req.provider)
        result = normalize_workout_analysis_result(raw)
        result["aiProvider"] = raw.get("aiProvider")
        result["aiModel"] = raw.get("aiModel")
        return result
    except Exception as error:
        error_text = str(error)
        print("BLAD TRAINER ANALYZE WORKOUT:", error_text)
        return trainer_error_result("analyze_workout", error_text)


@app.post("/generate-workout-plan")
@app.post("/workout/generate-plan")
async def generate_workout_plan(req: GenerateWorkoutPlanRequest):
    try:
        prompt = build_workout_plan_prompt(req)
        raw = await generate_text_json(prompt, req.ai_provider or req.provider)
        result = normalize_workout_plan_result(raw, req)
        result["aiProvider"] = raw.get("aiProvider")
        result["aiModel"] = raw.get("aiModel")
        return result
    except Exception as error:
        error_text = str(error)
        print("BLAD TRAINER GENERATE PLAN:", error_text)
        return trainer_error_result("generate_workout_plan", error_text)


@app.post("/analyze-exercise-form")
@app.post("/workout/analyze-form")
async def analyze_exercise_form(req: AnalyzeExerciseFormRequest):
    try:
        prompt = build_exercise_form_prompt(req)
        raw = await generate_text_json(prompt, req.ai_provider or req.provider)
        result = normalize_exercise_form_result(raw, req)
        result["aiProvider"] = raw.get("aiProvider")
        result["aiModel"] = raw.get("aiModel")
        return result
    except Exception as error:
        error_text = str(error)
        print("BLAD TRAINER ANALYZE FORM:", error_text)
        return trainer_error_result("analyze_exercise_form", error_text)


class TrainerChatRequest(BaseModel):
    message: str
    user: Optional[Dict[str, Any]] = None
    recent_logs: Optional[List[Any]] = None
    active_plan: Optional[Dict[str, Any]] = None
    # Pełny kontekst danych z aplikacji Trainer: regeneracja mięśni, ostatnie
    # 7 dni treningów (serie/RPE/objętość), aktywność i Health Connect,
    # korekta kcal/wody dla Licznika Kalorii, planer tygodnia.
    context: Optional[Dict[str, Any]] = None
    # Dodatkowe instrukcje z aplikacji (np. jak korzystać z kontekstu).
    instructions: Optional[str] = None
    history: Optional[List[Any]] = None
    ai_provider: Optional[str] = None
    provider: Optional[str] = None


def build_trainer_chat_prompt(req: TrainerChatRequest) -> str:
    history_text = ""
    if req.history:
        lines = []
        for item in req.history:
            if isinstance(item, dict):
                role = "Użytkownik" if str(item.get("role")) == "user" else "Trener"
                content = str(item.get("content") or "").strip()
                if content:
                    lines.append(f"{role}: {content}")
        history_text = "\n".join(lines)

    context_section = ""
    if req.context:
        context_section = f"""
Dane z aplikacji Trainer (kontekst — używaj ich jako źródła prawdy o użytkowniku;
zawiera: profil, dzisiejszą aktywność i Health Connect, ostatnie 7 dni treningów
z seriami/RPE/objętością, mapę regeneracji mięśni w %, biegi/cardio, plany
i programy 30-dniowe, korektę kcal/wody/makro wysyłaną do Licznika Kalorii
oraz propozycje planera tygodnia):
{json.dumps(req.context, ensure_ascii=False)}
"""

    instructions_section = ""
    if req.instructions:
        instructions_section = f"""
Instrukcje z aplikacji:
{req.instructions}
"""

    return f"""
Jesteś osobistym trenerem AI w aplikacji Trainer. Odpowiadasz po polsku, krótko,
praktycznie i konkretnie, jak doświadczony trener personalny.

Pytanie użytkownika:
"{req.message}"

Profil użytkownika:
{json.dumps(req.user or {}, ensure_ascii=False)}
{context_section}
Ostatnie treningi (starszy format — może być puste, gdy dane są w kontekście):
{json.dumps(req.recent_logs or [], ensure_ascii=False)}

Aktywny plan treningowy:
{json.dumps(req.active_plan or {}, ensure_ascii=False)}
{instructions_section}
Wcześniejsza rozmowa:
{history_text}

Zwróć WYŁĄCZNIE poprawny JSON, bez markdown i bez komentarzy.

Format:
{{
  "reply": "odpowiedź trenera po polsku, zwięzła i konkretna"
}}

Zasady:
- Bądź konkretny: jeśli pytanie dotyczy ciężaru, powtórzeń, odpoczynku albo techniki, daj jasną wskazówkę.
- Odpowiadaj na podstawie danych z sekcji "Dane z aplikacji Trainer": regeneracja
  mięśni (muscle_recovery), treningi z 7 dni (last_7_days), aktywność
  (cardio_activities, today.health_connect), korekta dla Licznika Kalorii
  (today.calorie_bridge) i planer tygodnia (weekly_planner).
- Podawaj liczby z danych (np. "triceps 44% regeneracji", "objętość 3200 kg"),
  zamiast ogólników.
- Nie diagnozuj medycznie. Przy bólu albo kontuzji zalecaj ostrożność i konsultację ze specjalistą.
- Nie zmieniaj planu użytkownika samodzielnie — możesz tylko zaproponować zmianę.
- Jeżeli danych brakuje w kontekście, powiedz wprost, jakich danych brakuje
  (np. brak zgód Health Connect, brak treningów), zamiast zgadywać.
"""


@app.post("/chat")
@app.post("/ai/chat")
async def trainer_chat(req: TrainerChatRequest):
    try:
        prompt = build_trainer_chat_prompt(req)
        raw = await generate_text_json(prompt, req.ai_provider or req.provider)
        reply = str(
            raw.get("reply")
            or raw.get("message")
            or raw.get("content")
            or raw.get("answer")
            or "Nie udało się przygotować odpowiedzi."
        )
        return {
            "reply": reply,
            "aiProvider": raw.get("aiProvider"),
            "aiModel": raw.get("aiModel"),
        }
    except Exception as error:
        error_text = str(error)
        print("BLAD TRAINER CHAT:", error_text)
        return {
            "reply": "Trener AI ma chwilowy problem z odpowiedzią. Spróbuj ponownie za moment.",
            "error": error_text,
            "kind": "trainer_chat",
        }


@app.post("/analyze-meal")
async def analyze_meal(
    file: UploadFile = File(...),
    description: str = Form(""),
    ai_provider: Optional[str] = Form(None),
    provider: Optional[str] = Form(None),
):
    image_bytes = await file.read()
    mime_type = get_mime_type(image_bytes)
    prompt = build_prompt(description)

    selected_provider = (ai_provider or provider or AI_PROVIDER).strip().lower()

    try:
        if selected_provider == "openai":
            return await analyze_with_openai(prompt, image_bytes, mime_type)

        if selected_provider == "gpt":
            return await analyze_with_openai(prompt, image_bytes, mime_type)

        if selected_provider == "gemini":
            return await analyze_with_gemini(prompt, image_bytes, mime_type)

        if selected_provider == "openai_then_gemini":
            try:
                return await analyze_with_openai(prompt, image_bytes, mime_type)
            except Exception as openai_error:
                print("OPENAI PADLO, PROBUJE GEMINI:", openai_error)
                return await analyze_with_gemini(prompt, image_bytes, mime_type)

        if selected_provider == "gemini_then_openai":
            try:
                return await analyze_with_gemini(prompt, image_bytes, mime_type)
            except Exception as gemini_error:
                print("GEMINI PADLO, PROBUJE OPENAI:", gemini_error)
                return await analyze_with_openai(prompt, image_bytes, mime_type)

        return error_result(
            "Błąd konfiguracji",
            f"Nieznany provider AI: {selected_provider}",
            "Ustaw provider jako openai, gpt albo gemini.",
        )

    except Exception as error:
        error_text = str(error)
        print("BLAD ANALIZY AI:", error_text)

        return error_result(
            "Błąd analizy",
            error_text,
            "Backend złapał błąd podczas analizy zdjęcia. Sprawdź Logs w Render albo popraw konfigurację API.",
        )
