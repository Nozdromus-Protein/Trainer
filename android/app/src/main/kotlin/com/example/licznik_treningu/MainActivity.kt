package com.example.licznik_treningu

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseRouteResult
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId

class MainActivity : FlutterFragmentActivity() {

    private val nativeChannelName = "trainer/health_native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            nativeChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "readExerciseRoutes" -> {
                    val dateKey = call.argument<String>("dateKey") ?: ""
                    CoroutineScope(Dispatchers.Main).launch {
                        readExerciseRoutes(dateKey, result)
                    }
                }

                "readExerciseSessions" -> {
                    val dateKey = call.argument<String>("dateKey") ?: ""
                    CoroutineScope(Dispatchers.Main).launch {
                        readExerciseSessions(dateKey, result)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun exerciseTypeName(type: Int): String = when (type) {
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL -> "RUNNING"
        ExerciseSessionRecord.EXERCISE_TYPE_WALKING,
        ExerciseSessionRecord.EXERCISE_TYPE_HIKING -> "WALKING"
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING,
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY -> "BIKING"
        else -> "OTHER_$type"
    }

    /**
     * Sesje treningowe z Health Connect wraz z DANYMI ZAREJESTROWANYMI PRZEZ
     * ZEGAREK / Samsung Health w oknie sesji (agregaty: kcal, dystans, kroki,
     * średnie i maksymalne tętno) + próbki tętna do stref pulsu.
     *
     * To jest główne źródło prawdy dla biegów/chodu — Trainer używa tych
     * wartości zamiast własnych wzorów (wzory zostają tylko jako fallback).
     */
    private suspend fun readExerciseSessions(dateKey: String, result: MethodChannel.Result) {
        try {
            if (HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE) {
                result.success(emptyList<Map<String, Any?>>())
                return
            }
            val zone = ZoneId.systemDefault()
            val day = try {
                LocalDate.parse(dateKey)
            } catch (e: Exception) {
                LocalDate.now(zone)
            }
            val start = day.atStartOfDay(zone).toInstant()
            val end = day.plusDays(1).atStartOfDay(zone).toInstant()

            val client = HealthConnectClient.getOrCreate(this)
            val sessions = client.readRecords(
                ReadRecordsRequest(
                    recordType = ExerciseSessionRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(start, end)
                )
            ).records

            val out = ArrayList<Map<String, Any?>>()
            for (session in sessions) {
                var distanceMeters = 0.0
                var activeKcal = 0.0
                var steps = 0L
                var avgHr = 0.0
                var maxHr = 0.0
                try {
                    val aggregate = client.aggregate(
                        AggregateRequest(
                            metrics = setOf(
                                DistanceRecord.DISTANCE_TOTAL,
                                ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL,
                                StepsRecord.COUNT_TOTAL,
                                HeartRateRecord.BPM_AVG,
                                HeartRateRecord.BPM_MAX
                            ),
                            timeRangeFilter = TimeRangeFilter.between(session.startTime, session.endTime)
                        )
                    )
                    distanceMeters = aggregate[DistanceRecord.DISTANCE_TOTAL]?.inMeters ?: 0.0
                    activeKcal = aggregate[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories ?: 0.0
                    steps = aggregate[StepsRecord.COUNT_TOTAL] ?: 0L
                    avgHr = (aggregate[HeartRateRecord.BPM_AVG] ?: 0L).toDouble()
                    maxHr = (aggregate[HeartRateRecord.BPM_MAX] ?: 0L).toDouble()
                } catch (e: Exception) {
                    // Agregaty są opcjonalne — sesja wróci z danymi podstawowymi.
                }

                // Próbki tętna (uśrednione do ~180 wartości) do stref pulsu.
                val hrSamples = ArrayList<Int>()
                try {
                    val hrRecords = client.readRecords(
                        ReadRecordsRequest(
                            recordType = HeartRateRecord::class,
                            timeRangeFilter = TimeRangeFilter.between(session.startTime, session.endTime)
                        )
                    ).records
                    val all = ArrayList<Int>()
                    for (record in hrRecords) {
                        for (sample in record.samples) all.add(sample.beatsPerMinute.toInt())
                    }
                    if (all.isNotEmpty()) {
                        val stride = maxOf(1, all.size / 180)
                        var index = 0
                        while (index < all.size) {
                            hrSamples.add(all[index])
                            index += stride
                        }
                    }
                } catch (e: Exception) {
                    // Brak tętna → puste strefy.
                }

                out.add(
                    mapOf(
                        "uuid" to session.metadata.id,
                        "type" to exerciseTypeName(session.exerciseType),
                        "title" to (session.title ?: ""),
                        "sourceName" to session.metadata.dataOrigin.packageName,
                        "start" to session.startTime.toString(),
                        "end" to session.endTime.toString(),
                        "distanceMeters" to distanceMeters,
                        "activeKcal" to activeKcal,
                        "steps" to steps.toInt(),
                        "avgHr" to avgHr,
                        "maxHr" to maxHr,
                        "hrSamples" to hrSamples
                    )
                )
            }
            result.success(out)
        } catch (e: Exception) {
            // Brak zgód / błąd → pusta lista, Dart użyje ścieżki pluginu.
            result.success(emptyList<Map<String, Any?>>())
        }
    }

    /**
     * Trasy GPS sesji treningowych (bieg/chód) z Health Connect dla jednego dnia.
     * Zwraca mapę: uuid sesji → lista punktów [lat, lng] (uproszczona do ~120).
     *
     * Defensywnie: brak Health Connect, brak zgody na trasy (ConsentRequired)
     * albo dowolny błąd → pusta mapa, bez crasha. Zgoda na trasy to osobne
     * uprawnienie „Trasy ćwiczeń" w Health Connect (READ_EXERCISE_ROUTES).
     */
    private suspend fun readExerciseRoutes(dateKey: String, result: MethodChannel.Result) {
        try {
            if (HealthConnectClient.getSdkStatus(this) != HealthConnectClient.SDK_AVAILABLE) {
                result.success(emptyMap<String, Any?>())
                return
            }
            val zone = ZoneId.systemDefault()
            val day = try {
                LocalDate.parse(dateKey)
            } catch (e: Exception) {
                LocalDate.now(zone)
            }
            val start = day.atStartOfDay(zone).toInstant()
            val end = day.plusDays(1).atStartOfDay(zone).toInstant()

            val client = HealthConnectClient.getOrCreate(this)
            val records = client.readRecords(
                ReadRecordsRequest(
                    recordType = ExerciseSessionRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(start, end)
                )
            ).records

            val out = HashMap<String, Any?>()
            for (record in records) {
                val routeResult = record.exerciseRouteResult
                if (routeResult is ExerciseRouteResult.Data) {
                    val points = routeResult.exerciseRoute.route
                    if (points.size >= 2) {
                        val stride = maxOf(1, points.size / 120)
                        val simplified = ArrayList<List<Double>>()
                        var index = 0
                        while (index < points.size) {
                            val point = points[index]
                            simplified.add(listOf(point.latitude, point.longitude))
                            index += stride
                        }
                        // Zawsze domknij trasę ostatnim punktem.
                        val last = points.last()
                        if (simplified.isEmpty() ||
                            simplified.last()[0] != last.latitude ||
                            simplified.last()[1] != last.longitude
                        ) {
                            simplified.add(listOf(last.latitude, last.longitude))
                        }
                        out[record.metadata.id] = simplified
                    }
                }
            }
            result.success(out)
        } catch (e: Exception) {
            // Brak zgody na trasy / błąd odczytu → bieg pokaże się bez mapy.
            result.success(emptyMap<String, Any?>())
        }
    }
}
