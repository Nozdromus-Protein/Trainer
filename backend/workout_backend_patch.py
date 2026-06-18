"""
Endpointy treningowe do backendu FastAPI używanego przez aplikację „Licznik Kalorii”.

Jak użyć:
1. Wklej ten plik albo jego zawartość do obecnego main.py backendu.
2. Upewnij się, że masz ENV:
   GEMINI_API_KEYS=klucz1,klucz2,klucz3
   GEMINI_MODEL=gemini-2.5-flash
3. Endpointy:
   POST /analyze-workout
   POST /generate-workout-plan
   POST /analyze-exercise-form

Kod jest celowo samodzielny, żeby działał nawet wtedy, gdy nazwy Twoich obecnych funkcji Gemini są inne.
Jeśli w main.py masz już własną funkcję czyszczenia JSON i rotacji kluczy, możesz podmienić _call_gemini_json na swoją.
"""

import json
import os
import random
import re
from typing import Any, Dict, List, Optional

import requests
from fastapi import HTTPException
from pydantic import BaseModel, Field

GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
GEMINI_API_KEYS_RAW = os.getenv("GEMINI_API_KEYS", "")
GEMINI_API_KEYS = [k.strip() for k in GEMINI_API_KEYS_RAW.split(",") if k.strip()]


def _extract_json(text: str) -> Dict[str, Any]:
    """Czyści odpowiedź modelu do JSON-a, podobnie jak w backendzie licznika kalorii."""
    if not text:
        raise ValueError("Pusta odpowiedź AI")
    text = text.strip()
    text = re.sub(r"^```(?:json)?", "", text, flags=re.IGNORECASE).strip()
    text = re.sub(r"```$", "", text).strip()

    try:
        data = json.loads(text)
        if isinstance(data, dict):
            return data
    except Exception:
        pass

    start = text.find("{")
    end = text.rfind("}")
    if start >= 0 and end > start:
        data = json.loads(text[start : end + 1])
        if isinstance(data, dict):
            return data

    raise ValueError("Nie udało się odczytać JSON z odpowiedzi AI")


def _call_gemini_json(prompt: str) -> Dict[str, Any]:
    if not GEMINI_API_KEYS:
        raise HTTPException(status_code=500, detail="Brak GEMINI_API_KEYS w ENV backendu")

    keys = GEMINI_API_KEYS[:]
    random.shuffle(keys)
    last_error = None

    for key in keys:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent?key={key}"
        payload = {
            "contents": [
                {
                    "role": "user",
                    "parts": [{"text": prompt}],
                }
            ],
            "generationConfig": {
                "temperature": 0.25,
                "responseMimeType": "application/json",
            },
        }
        try:
            response = requests.post(url, json=payload, timeout=45)
            if response.status_code == 429:
                last_error = "429 quota/rate limit"
                continue
            if response.status_code >= 500:
                last_error = f"Gemini {response.status_code}: {response.text[:300]}"
                continue
            if response.status_code >= 400:
                raise HTTPException(status_code=response.status_code, detail=response.text)

            raw = response.json()
            text = raw["candidates"][0]["content"]["parts"][0]["text"]
            return _extract_json(text)
        except HTTPException:
            raise
        except Exception as exc:
            last_error = str(exc)
            continue

    raise HTTPException(status_code=503, detail=f"AI niedostępne lub limit kluczy. Ostatni błąd: {last_error}")


class WorkoutUserProfile(BaseModel):
    body_weight_kg: Optional[float] = 100
    height_cm: Optional[float] = 185
    age: Optional[int] = 28
    goal: Optional[str] = "rekompozycja"
    level: Optional[str] = "średniozaawansowany"
    training_weekdays: Optional[List[int]] = Field(default_factory=lambda: [1, 2, 3, 4, 5, 6])


class AnalyzeWorkoutRequest(BaseModel):
    description: str
    date: Optional[str] = None
    user: Optional[WorkoutUserProfile] = None


class GenerateWorkoutPlanRequest(BaseModel):
    goal: str
    days_per_week: int = 4
    equipment: Optional[str] = "masa ciała"
    limitations: Optional[str] = ""
    level: Optional[str] = "średniozaawansowany"
    user: Optional[WorkoutUserProfile] = None


class AnalyzeExerciseFormRequest(BaseModel):
    exercise: str
    notes: str
    user: Optional[WorkoutUserProfile] = None


@app.post("/analyze-workout")
def analyze_workout(req: AnalyzeWorkoutRequest):
    user = (req.user or WorkoutUserProfile()).model_dump()
    prompt = f"""
Jesteś trenerem personalnym i analizatorem dziennika treningowego.
Użytkownik prowadzi aplikację do treningu połączoną z licznikiem kalorii.

Profil użytkownika:
{json.dumps(user, ensure_ascii=False)}

Opis treningu użytkownika:
{req.description}

Zwróć WYŁĄCZNIE poprawny JSON bez markdowna.
Schemat:
{{
  "confidence": 0.0-1.0,
  "summary": "krótkie podsumowanie po polsku",
  "estimated_total_calories": liczba,
  "estimated_duration_min": liczba,
  "training_type": "siłowy/kardio/mieszany/mobilność",
  "fatigue_score": 1-10,
  "logs": [
    {{
      "exercise": "nazwa ćwiczenia po polsku",
      "sets": liczba,
      "reps": liczba lub 0,
      "weight_kg": liczba lub 0,
      "duration_sec": liczba lub 0,
      "rpe": 1-10,
      "calories": liczba,
      "muscles": ["partia 1", "partia 2"],
      "note": "krótka notatka"
    }}
  ],
  "suggestions": ["konkretna sugestia 1", "konkretna sugestia 2"],
  "next_workout_hint": "co zrobić następnym razem"
}}
"""
    return _call_gemini_json(prompt)


@app.post("/generate-workout-plan")
def generate_workout_plan(req: GenerateWorkoutPlanRequest):
    user = (req.user or WorkoutUserProfile()).model_dump()
    days = max(2, min(6, req.days_per_week))
    prompt = f"""
Stwórz plan treningowy dla aplikacji mobilnej.
Ma być praktyczny, bezpieczny i możliwy do zapisania jako JSON.

Profil użytkownika:
{json.dumps(user, ensure_ascii=False)}

Cel: {req.goal}
Poziom: {req.level}
Liczba dni: {days}
Sprzęt: {req.equipment}
Ograniczenia/uwagi: {req.limitations}

Zasady:
- Używaj polskich nazw ćwiczeń.
- Uwzględnij brzuch/core, nogi, klatkę, plecy i ręce.
- Jeśli celem jest brzuch i rekompozycja, dodaj ćwiczenia z obciążeniem i progresję.
- Nie przeciążaj jednego ruchu codziennie.
- Daj konkretne serie, powtórzenia albo czas.

Zwróć WYŁĄCZNIE poprawny JSON bez markdowna.
Schemat:
{{
  "name": "nazwa planu",
  "confidence": 0.0-1.0,
  "note": "krótka notatka",
  "days": [
    {{
      "weekday": 1-7,
      "title": "np. Nogi + brzuch",
      "items": [
        {{
          "exercise": "Przysiad",
          "sets": 4,
          "reps": 10,
          "duration_sec": 0,
          "note": "tempo/progresja/uwaga"
        }}
      ]
    }}
  ],
  "progression": ["tydzień 1...", "tydzień 2..."],
  "safety": ["zasada 1", "zasada 2"]
}}
"""
    return _call_gemini_json(prompt)


@app.post("/analyze-exercise-form")
def analyze_exercise_form(req: AnalyzeExerciseFormRequest):
    user = (req.user or WorkoutUserProfile()).model_dump()
    prompt = f"""
Jesteś trenerem personalnym. Użytkownik opisuje technikę lub odczucia podczas ćwiczenia.
Nie diagnozuj medycznie. Jeśli opis sugeruje ból ostry, drętwienie, promieniowanie albo uraz, zalec przerwanie ćwiczenia i konsultację ze specjalistą.

Profil:
{json.dumps(user, ensure_ascii=False)}

Ćwiczenie: {req.exercise}
Opis użytkownika: {req.notes}

Zwróć WYŁĄCZNIE JSON:
{{
  "confidence": 0.0-1.0,
  "risk_level": "niski/średni/wysoki",
  "summary": "krótkie podsumowanie",
  "likely_issues": ["problem 1", "problem 2"],
  "corrections": ["konkretna poprawka 1", "konkretna poprawka 2"],
  "warmup": ["ćwiczenie rozgrzewkowe 1", "ćwiczenie rozgrzewkowe 2"],
  "when_to_stop": ["sygnał ostrzegawczy 1", "sygnał ostrzegawczy 2"]
}}
"""
    return _call_gemini_json(prompt)
