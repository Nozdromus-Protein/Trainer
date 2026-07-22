"""Testy endpointu analizy treningu (/analyze-workout).

Kluczowa regresja: request BEZ pola `description` zwracał HTTP 422
("Field required", loc: ["body", "description"]), bo model Pydantic wymagał
tego pola, a aplikacja wysyłała wyłącznie ustrukturyzowane dane sesji.

Testy nie wołają zewnętrznego AI — sprawdzają walidację modelu i budowanie
opisu z danych sesji.
"""

import pytest
from fastapi.testclient import TestClient

import main
from main import AnalyzeWorkoutRequest, app, build_description_from_session


@pytest.fixture()
def client(monkeypatch):
    """Klient HTTP z zamockowanym AI — testujemy kontrakt, nie dostawcę modelu."""

    async def fake_generate(prompt, provider=None):
        return {
            "summary": "Solidny trening.",
            "aiProvider": "test",
            "aiModel": "test-model",
        }

    monkeypatch.setattr(main, "generate_text_json", fake_generate)
    return TestClient(app)


def test_post_without_description_does_not_return_422(client):
    """Regresja: request bez `description` MUSI przejść (wcześniej HTTP 422)."""
    response = client.post(
        "/analyze-workout",
        json={
            "session": {"name": "Plan · Dzień 1", "duration_minutes": 45},
            "exercises": [{"name": "Deska", "sets": 2, "duration_sec": 50}],
            "user": {"level": "Średniozaawansowany"},
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert "error" not in body or not body["error"]


def test_post_with_description_still_works(client):
    response = client.post(
        "/analyze-workout",
        json={"description": "Trening nóg.", "user": {}},
    )
    assert response.status_code == 200


def test_legacy_alias_route_without_description(client):
    response = client.post("/workout/analyze", json={"session": {"name": "X"}})
    assert response.status_code == 200


def test_request_without_description_is_valid():
    """Brak `description` NIE może być błędem walidacji (wcześniej HTTP 422)."""
    req = AnalyzeWorkoutRequest(
        session={"name": "Plan · Dzień 1", "duration_minutes": 45, "set_count": 8},
        exercises=[{"name": "Deska", "sets": 2, "duration_sec": 50}],
        user={"level": "Średniozaawansowany"},
    )
    assert req.description is None
    # Opis efektywny jest składany z danych sesji, a nie pusty.
    assert "Deska" in req.effective_description()


def test_request_keeps_explicit_description():
    req = AnalyzeWorkoutRequest(description="Trening nóg, 5 serii przysiadów.")
    assert req.effective_description() == "Trening nóg, 5 serii przysiadów."


def test_structured_fields_are_not_dropped():
    """Sesja/ćwiczenia/historia muszą dotrzeć do modelu (wcześniej ignorowane)."""
    req = AnalyzeWorkoutRequest(
        description="opis",
        session={"name": "X"},
        exercises=[{"name": "Deska", "sets": 2}],
        recent_history=[{"date": "2026-07-15", "exercises": []}],
    )
    assert req.session == {"name": "X"}
    assert req.exercises[0]["name"] == "Deska"
    assert req.recent_history[0]["date"] == "2026-07-15"


def test_build_description_from_session_has_stats_and_exercises():
    text = build_description_from_session(
        {
            "name": "Plan · Dzień 1",
            "duration_minutes": 45,
            "exercise_count": 2,
            "set_count": 6,
            "volume_kg": 1200,
            "average_rpe": 7.5,
        },
        [
            {"name": "Wyciskanie", "sets": 3, "reps": 10, "weight_kg": 40},
            {"name": "Deska", "sets": 2, "duration_sec": 50},
        ],
    )
    assert "Plan · Dzień 1" in text
    assert "45 min" in text
    assert "Wyciskanie" in text and "40 kg" in text
    assert "Deska" in text and "50 s" in text


def test_build_description_from_empty_session_is_not_empty():
    """Nawet bez danych opis nie może być pusty (prompt musi mieć treść)."""
    assert build_description_from_session(None, None).strip()


def test_prompt_builds_without_description():
    """Prompt musi się zbudować dla requestu bez `description` i zawierać dane."""
    req = AnalyzeWorkoutRequest(
        session={"name": "Plan · Dzień 1", "duration_minutes": 30},
        exercises=[{"name": "Deska", "sets": 2, "duration_sec": 50}],
    )
    prompt = main.build_workout_analysis_prompt(req)
    assert "Deska" in prompt
    # Nie może zostać dosłowne "None" jako opis treningu.
    assert '"None"' not in prompt
