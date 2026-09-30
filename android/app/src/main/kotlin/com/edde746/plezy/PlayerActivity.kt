package com.edde746.plezy

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Gravity
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.Button
import android.widget.FrameLayout
import android.widget.ArrayAdapter
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import android.widget.Toast
import com.google.android.exoplayer2.audio.AudioAttributes
import com.google.android.exoplayer2.C
import com.google.android.exoplayer2.ExoPlayer
import com.google.android.exoplayer2.Format
import com.google.android.exoplayer2.MediaItem
import com.google.android.exoplayer2.Player
import com.google.android.exoplayer2.Tracks
import com.google.android.exoplayer2.analytics.AnalyticsListener
import com.google.android.exoplayer2.source.DefaultMediaSourceFactory
import com.google.android.exoplayer2.trackselection.DefaultTrackSelector
import com.google.android.exoplayer2.ui.StyledPlayerView
import com.google.android.exoplayer2.upstream.DefaultAllocator
import com.google.android.exoplayer2.DefaultLoadControl
import com.google.android.exoplayer2.ext.okhttp.OkHttpDataSource
import com.google.android.exoplayer2.upstream.DataSource
import com.google.android.exoplayer2.upstream.DataSpec
import com.google.android.exoplayer2.upstream.HttpDataSource
import com.google.android.exoplayer2.upstream.TransferListener
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.atomic.AtomicLong

class PlayerActivity : Activity() {
    private data class Marker(val type: String, val startMs: Long, val endMs: Long)
    private data class NativeSubtitleTrack(
        val rendererIndex: Int,
        val groupIndex: Int,
        val trackIndex: Int,
        val label: String,
        val candidate: MediaTrackCandidate,
    )
    private data class NativeAudioTrack(
        val rendererIndex: Int,
        val groupIndex: Int,
        val trackIndex: Int,
        val label: String,
        val candidate: MediaTrackCandidate,
    )

    private var player: ExoPlayer? = null
    private var ended = false
    private var playbackError: String? = null
    private val diagnostics = PlaybackDiagnostics()
    private var failureKind: String? = null
    @Volatile private var completed = false
    @Volatile private var renderedFirstFrame = false
    private var firstFrameMs = -1L
    private var decoderName: String? = null
    private var videoFormat: String? = null
    private var playerStartedAtMs = 0L
    private var automaticRetries = 0
    private var wasPlayingBeforePause = false
    private var activityPaused = false
    private var playerView: StyledPlayerView? = null
    private var trackSelector: DefaultTrackSelector? = null
    private var skipButton: Button? = null
    private var controlPanel: LinearLayout? = null
    private var playPauseButton: Button? = null
    private var audioButton: Button? = null
    private var captionsButton: Button? = null
    private var seekBar: SeekBar? = null
    private var positionLabel: TextView? = null
    private var userSeeking = false
    private var initialSubtitleApplied = false
    private var initialAudioApplied = false
    private var activeSubtitle: NativeSubtitleTrack? = null
    private var activeAudio: NativeAudioTrack? = null
    private var requestedAudioId = ""
    private var requestedAudioLanguage = ""
    private var requestedAudioTitle = ""
    private var requestedAudioCodec = ""
    private var requestedSubtitleId = ""
    private var requestedSubtitleLanguage = ""
    private var requestedSubtitleTitle = ""
    private var requestedSubtitleCodec = ""
    private var requestedSubtitleUrl = ""
    private var plexAudioIds: List<String> = emptyList()
    private var plexSubtitleIds: List<String> = emptyList()
    private var sideloadedSubtitleId: String? = null
    private var userAudioChoice: NativeAudioTrack? = null
    private var userSubtitleChoice: NativeSubtitleTrack? = null
    private var userChangedSubtitle = false
    private var recoveredAtMs = 0L
    private var markers: List<Marker> = emptyList()
    private var skipMode = "button"
    private val skippedMarkerIndexes = mutableSetOf<Int>()
    private var seekBackMs = 10_000L
    private var seekForwardMs = 30_000L
    private var pendingSeekPositionMs: Long? = null
    private var startupHardTimeoutMs = 120_000L
    @Volatile private var startupAttemptStartedAtMs = 0L
    @Volatile private var lastStartupProgressAtMs = 0L
    private var lastBufferedPositionMs = -1L
    private var readyWithoutFrameAtMs = 0L
    private val startupNetworkBytes = AtomicLong(0L)
    private val seekRunnable = Runnable {
        val target = pendingSeekPositionMs
        pendingSeekPositionMs = null
        if (target != null && !completed) player?.seekTo(target)
    }
    private val hideControlsRunnable = Runnable {
        if (player?.isPlaying == true) controlPanel?.visibility = View.GONE
    }
    private val startupTransferListener = object : TransferListener {
        override fun onTransferInitializing(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit

        override fun onTransferStart(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit

        override fun onBytesTransferred(
            source: DataSource,
            dataSpec: DataSpec,
            isNetwork: Boolean,
            bytesTransferred: Int,
        ) {
            if (isNetwork && bytesTransferred > 0 && !renderedFirstFrame && !completed) {
                startupNetworkBytes.addAndGet(bytesTransferred.toLong())
                lastStartupProgressAtMs = SystemClock.elapsedRealtime()
            }
        }

        override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit
    }
    private val timelineHandler = Handler(Looper.getMainLooper())
    private var requestHeaders: Map<String, String> = emptyMap()
    private var timelineUrl = ""
    private var sessionId = ""
    private var ratingKey = ""
    private var mediaDurationMs = 0L
    private var playbackHttpClient: OkHttpClient? = null
    private var lastTimelineReportAt = 0L
    private val timelineRunnable = object : Runnable {
        override fun run() {
            val exo = player ?: return
            val now = SystemClock.elapsedRealtime()
            if (exo.isPlaying && now - lastTimelineReportAt >= 10_000L) {
                lastTimelineReportAt = now
                reportTimeline(exo.currentPosition, "playing")
            }
            updateCarControls(exo)
            resetReconnectBudgetIfStable(exo, now)
            checkStartupProgress(exo, now)
            if (completed) return
            updateSkipButton(exo.currentPosition)
            timelineHandler.postDelayed(this, 500L)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        hideSystemUi()

        val url = intent.getStringExtra(EXTRA_URL)
        if (url.isNullOrBlank()) {
            finishWithResult("Missing playback URL")
            return
        }

        val keys = intent.getStringArrayExtra(EXTRA_HEADERS_KEYS) ?: emptyArray()
        val values = intent.getStringArrayExtra(EXTRA_HEADERS_VALUES) ?: emptyArray()
        val headers = linkedMapOf<String, String>()
        for (index in 0 until minOf(keys.size, values.size)) headers[keys[index]] = values[index]
        requestHeaders = headers
        timelineUrl = intent.getStringExtra(EXTRA_TIMELINE_URL) ?: ""
        sessionId = intent.getStringExtra(EXTRA_SESSION_ID) ?: ""
        ratingKey = intent.getStringExtra(EXTRA_RATING_KEY) ?: ""
        mediaDurationMs = intent.getLongExtra(EXTRA_DURATION_MS, 0L)
        seekBackMs = intent.getLongExtra(EXTRA_SEEK_BACK_MS, 10_000L)
        seekForwardMs = intent.getLongExtra(EXTRA_SEEK_FORWARD_MS, 30_000L)
        skipMode = intent.getStringExtra(EXTRA_SKIP_MODE) ?: "button"
        startupHardTimeoutMs = intent.getLongExtra(EXTRA_STARTUP_HARD_TIMEOUT_MS, 120_000L)
        val markerTypes = intent.getStringArrayListExtra(EXTRA_MARKER_TYPES) ?: arrayListOf()
        val markerStarts = intent.getLongArrayExtra(EXTRA_MARKER_STARTS) ?: longArrayOf()
        val markerEnds = intent.getLongArrayExtra(EXTRA_MARKER_ENDS) ?: longArrayOf()
        markers = (0 until minOf(markerTypes.size, markerStarts.size, markerEnds.size)).map {
            Marker(markerTypes[it], markerStarts[it], markerEnds[it])
        }

        try {
            initializePlayer(url, headers)
        } catch (error: Exception) {
            failureKind = "initialization"
            finishWithResult("PLAYER_INITIALIZATION: ${PlaybackDiagnostics.describe(error)}")
        } catch (error: LinkageError) {
            failureKind = "initialization"
            finishWithResult("PLAYER_LINKAGE: ${PlaybackDiagnostics.describe(error)}")
        }
    }

    private fun initializePlayer(url: String, headers: Map<String, String>) {
        require(Uri.parse(url).scheme == "https") { "Playback requires HTTPS" }
        diagnostics.add("Player: native HTTPS, TLS 1.2, Plex Generation-Y trust")
        val okHttpClient = LegacyTls.createClient(this, diagnostics)
        playbackHttpClient = okHttpClient
        val httpFactory = OkHttpDataSource.Factory(okHttpClient)
            .setDefaultRequestProperties(headers)
            .setTransferListener(startupTransferListener)

        // Small buffers are intentional: this head unit reports a 64 MiB app heap.
        val loadControl = DefaultLoadControl.Builder()
            .setAllocator(DefaultAllocator(true, C.DEFAULT_BUFFER_SEGMENT_SIZE))
            .setBufferDurationsMs(5_000, 18_000, 1_000, 2_500)
            .setTargetBufferBytes(12 * 1024 * 1024)
            .setPrioritizeTimeOverSizeThresholds(false)
            .build()
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .build()
        val trackSelector = DefaultTrackSelector(this)
        this.trackSelector = trackSelector
        val trackParameters = trackSelector.buildUponParameters()
        requestedAudioLanguage = intent.getStringExtra(EXTRA_AUDIO_LANGUAGE).orEmpty()
        requestedAudioId = intent.getStringExtra(EXTRA_AUDIO_TRACK_ID).orEmpty()
        requestedAudioTitle = intent.getStringExtra(EXTRA_AUDIO_TITLE).orEmpty()
        requestedAudioCodec = intent.getStringExtra(EXTRA_AUDIO_CODEC).orEmpty()
        requestedSubtitleLanguage = intent.getStringExtra(EXTRA_SUBTITLE_LANGUAGE).orEmpty()
        requestedSubtitleId = intent.getStringExtra(EXTRA_SUBTITLE_TRACK_ID).orEmpty()
        requestedSubtitleTitle = intent.getStringExtra(EXTRA_SUBTITLE_TITLE).orEmpty()
        requestedSubtitleCodec = intent.getStringExtra(EXTRA_SUBTITLE_CODEC).orEmpty()
        requestedSubtitleUrl = intent.getStringExtra(EXTRA_SUBTITLE_URL).orEmpty()
        plexAudioIds = intent.getStringArrayExtra(EXTRA_AUDIO_TRACK_IDS)?.toList().orEmpty()
        plexSubtitleIds = intent.getStringArrayExtra(EXTRA_SUBTITLE_TRACK_IDS)?.toList().orEmpty()
        if (requestedAudioLanguage.isNotBlank()) {
            trackParameters.setPreferredAudioLanguage(requestedAudioLanguage)
        }
        if (requestedSubtitleLanguage == "off" || requestedSubtitleId == "off") {
            trackParameters.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        } else {
            trackParameters.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            if (requestedSubtitleLanguage.isNotBlank()) {
                trackParameters.setPreferredTextLanguage(requestedSubtitleLanguage)
            }
            if (requestedSubtitleId.isNotBlank() || requestedSubtitleUrl.isNotBlank()) {
                trackParameters.setSelectUndeterminedTextLanguage(true)
            }
        }
        if (requestedAudioId.isNotBlank()) diagnostics.add("Audio selection: Plex track $requestedAudioId")
        if (requestedSubtitleId.isNotBlank()) diagnostics.add("Subtitle selection: Plex track $requestedSubtitleId")
        diagnostics.add("Player setup: configuring track preferences")
        trackSelector.parameters = trackParameters.build()
        diagnostics.add("Player setup: creating ExoPlayer")
        val exo = ExoPlayer.Builder(this)
            .setMediaSourceFactory(DefaultMediaSourceFactory(httpFactory))
            .setLoadControl(loadControl)
            .setTrackSelector(trackSelector)
            .setSeekBackIncrementMs(seekBackMs)
            .setSeekForwardIncrementMs(seekForwardMs)
            .setAudioAttributes(audioAttributes, true)
            .setHandleAudioBecomingNoisy(true)
            .build()
        player = exo
        diagnostics.add("Player setup: creating video surface")

        val view = StyledPlayerView(this).apply {
            useController = false
            setShowBuffering(StyledPlayerView.SHOW_BUFFERING_ALWAYS)
            keepScreenOn = true
            player = exo
            contentDescription = intent.getStringExtra(EXTRA_TITLE) ?: "Plezy player"
            subtitleView?.setFractionalTextSize(0.062f)
            subtitleView?.setBottomPaddingFraction(0.12f)
        }
        playerView = view
        val root = FrameLayout(this)
        root.addView(view, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.MATCH_PARENT,
            FrameLayout.LayoutParams.MATCH_PARENT,
        ))
        try {
            root.addView(createCarControls(), FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM,
            ))
            diagnostics.add("Player controls: GKUI large-touch overlay")
        } catch (error: LinkageError) {
            clearCustomControlReferences()
            view.useController = true
            view.setShowSubtitleButton(true)
            diagnostics.add("Player controls: stock compatibility fallback (${describeLinkage(error)})")
        }
        view.setOnClickListener { toggleControls() }
        val skip = Button(this).apply {
            visibility = View.GONE
            textSize = 20f
            minHeight = dp(64)
            minWidth = dp(170)
            setTextColor(Color.WHITE)
            background = carButtonBackground(0xEEFF9800.toInt())
            setOnClickListener {
                val active = activeMarker(player?.currentPosition ?: -1L)
                if (active != null) player?.seekTo(active.endMs)
                showControls()
            }
        }
        skipButton = skip
        root.addView(skip, FrameLayout.LayoutParams(
            FrameLayout.LayoutParams.WRAP_CONTENT,
            FrameLayout.LayoutParams.WRAP_CONTENT,
            Gravity.END or Gravity.CENTER_VERTICAL,
        ).apply { setMargins(0, 0, dp(28), 0) })
        setContentView(root)
        showControls()

        exo.addAnalyticsListener(object : AnalyticsListener {
            override fun onVideoDecoderInitialized(
                eventTime: AnalyticsListener.EventTime,
                decoderNameValue: String,
                initializedTimestampMs: Long,
                initializationDurationMs: Long,
            ) {
                decoderName = decoderNameValue
                diagnostics.add("Decoder: $decoderNameValue")
            }
        })

        exo.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (!renderedFirstFrame) {
                    lastStartupProgressAtMs = SystemClock.elapsedRealtime()
                    if (state != Player.STATE_READY) readyWithoutFrameAtMs = 0L
                }
                diagnostics.add("Player state: " + when (state) {
                    Player.STATE_IDLE -> "idle"
                    Player.STATE_BUFFERING -> "buffering"
                    Player.STATE_READY -> "ready"
                    Player.STATE_ENDED -> "ended"
                    else -> "unknown"
                })
                if (state == Player.STATE_READY && automaticRetries > 0 && recoveredAtMs == 0L) {
                    recoveredAtMs = SystemClock.elapsedRealtime()
                } else if (state != Player.STATE_READY) {
                    recoveredAtMs = 0L
                }
                updateCarControls(exo)
                if (state == Player.STATE_ENDED) {
                    ended = true
                    window.decorView.postDelayed({ finishWithResult(null) }, 350L)
                }
            }

            override fun onTracksChanged(tracks: Tracks) {
                val audioRequested = requestedAudioId.isNotBlank() ||
                    requestedAudioLanguage.isNotBlank()
                if (!initialAudioApplied && audioRequested) {
                    initialAudioApplied = true
                    try {
                        applyRequestedAudio()
                    } catch (error: LinkageError) {
                        diagnostics.add("Audio selection fallback: ${describeLinkage(error)}")
                    } catch (error: RuntimeException) {
                        diagnostics.add("Audio selection fallback: ${PlaybackDiagnostics.describe(error)}")
                    }
                }
                val subtitleRequested = requestedSubtitleId.isNotBlank() ||
                    requestedSubtitleLanguage.isNotBlank() || requestedSubtitleUrl.isNotBlank()
                if (!initialSubtitleApplied && subtitleRequested &&
                    requestedSubtitleId != "off" && requestedSubtitleLanguage != "off"
                ) {
                    initialSubtitleApplied = true
                    try {
                        applyRequestedSubtitle()
                    } catch (error: LinkageError) {
                        diagnostics.add("Subtitle selection fallback: ${describeLinkage(error)}")
                    } catch (error: RuntimeException) {
                        diagnostics.add("Subtitle selection fallback: ${PlaybackDiagnostics.describe(error)}")
                    }
                }
                syncActiveTracks(tracks)
            }

            override fun onRenderedFirstFrame() {
                renderedFirstFrame = true
                firstFrameMs = SystemClock.elapsedRealtime() - playerStartedAtMs
                videoFormat = describeVideoFormat(exo.videoFormat)
                diagnostics.add("Player: first video frame in ${firstFrameMs}ms")
                diagnostics.add("Startup network: ${formatNetworkBytes(startupNetworkBytes.get())}")
                if (videoFormat != null) diagnostics.add("Video format: $videoFormat")
            }

            override fun onPlayerError(error: com.google.android.exoplayer2.PlaybackException) {
                val http = PlaybackDiagnostics.causes(error)
                    .filterIsInstance<HttpDataSource.InvalidResponseCodeException>().firstOrNull()
                failureKind = when {
                    PlaybackDiagnostics.isConnectionFailure(error) || error.errorCode == 2001 -> "network"
                    http != null -> "http"
                    error.errorCode in 4000..4999 -> "decoder"
                    else -> "source"
                }
                playbackError = "${error.errorCodeName}: ${PlaybackDiagnostics.describe(error)}" +
                    (http?.let { "; HTTP ${it.responseCode}" } ?: "")
                diagnostics.add("Player failed: $playbackError")
                if (failureKind == "network" && automaticRetries < 2 && !completed) {
                    automaticRetries += 1
                    diagnostics.add("Player: reconnect retry $automaticRetries of 2")
                    window.decorView.postDelayed({
                        if (!completed) {
                            playbackError = null
                            val retryStartedAt = SystemClock.elapsedRealtime()
                            startupAttemptStartedAtMs = retryStartedAt
                            lastStartupProgressAtMs = retryStartedAt
                            lastBufferedPositionMs = exo.bufferedPosition
                            readyWithoutFrameAtMs = 0L
                            recoveredAtMs = 0L
                            exo.prepare()
                            exo.playWhenReady = true
                        }
                    }, 1_500L * automaticRetries)
                    return
                }
                window.decorView.post { finishWithResult(playbackError) }
            }
        })
        val mediaItemBuilder = MediaItem.Builder().setUri(Uri.parse(url))
        if (requestedSubtitleUrl.isNotBlank()) {
            val subtitleUri = Uri.parse(requestedSubtitleUrl)
            val mimeType = MediaTrackSelectionPolicy.subtitleMimeType(
                requestedSubtitleCodec,
                requestedSubtitleUrl,
            )
            if (subtitleUri.scheme == "https" && mimeType != null) {
                val sideloadedId = requestedSubtitleId.ifBlank { "plex-external" }
                sideloadedSubtitleId = sideloadedId
                val subtitleBuilder = MediaItem.SubtitleConfiguration.Builder(subtitleUri)
                    .setId(sideloadedId)
                    .setMimeType(mimeType)
                    .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                if (requestedSubtitleLanguage.isNotBlank()) {
                    subtitleBuilder.setLanguage(requestedSubtitleLanguage)
                }
                if (requestedSubtitleTitle.isNotBlank()) {
                    subtitleBuilder.setLabel(requestedSubtitleTitle)
                }
                mediaItemBuilder.setSubtitleConfigurations(listOf(subtitleBuilder.build()))
                diagnostics.add("Subtitle source: external ${requestedSubtitleCodec.ifBlank { mimeType }}")
            } else {
                diagnostics.add("Subtitle source unsupported: ${requestedSubtitleCodec.ifBlank { "unknown" }}")
            }
        }
        exo.setMediaItem(mediaItemBuilder.build())
        diagnostics.add("Player setup: media item attached")
        val startMs = intent.getLongExtra(EXTRA_START_MS, 0L)
        if (startMs > 0L) exo.seekTo(startMs)
        playerStartedAtMs = SystemClock.elapsedRealtime()
        startupAttemptStartedAtMs = playerStartedAtMs
        lastStartupProgressAtMs = playerStartedAtMs
        lastBufferedPositionMs = exo.bufferedPosition
        diagnostics.add("Startup watchdog: 30s without buffer or network progress / ${startupHardTimeoutMs / 1_000L}s maximum")
        exo.prepare()
        exo.playWhenReady = true
        timelineHandler.post(timelineRunnable)
    }

    private fun createCarControls(): LinearLayout {
        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(10), dp(18), dp(12))
            background = GradientDrawable().apply { setColor(0xE6161616.toInt()) }
        }
        controlPanel = panel

        val time = TextView(this).apply {
            text = "00:00 / --:--"
            textSize = 18f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        positionLabel = time
        panel.addView(time, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(30),
        ))

        val progress = SeekBar(this).apply {
            max = 1_000
            // Do not set minHeight here: on a SeekBar it resolves to
            // ProgressBar.setMinHeight, which only exists from API 29. The
            // 48dp LayoutParams below already give the bar its touch height.
            contentDescription = "Playback position"
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onStartTrackingTouch(seekBar: SeekBar) {
                    userSeeking = true
                    timelineHandler.removeCallbacks(hideControlsRunnable)
                }

                override fun onProgressChanged(seekBar: SeekBar, value: Int, fromUser: Boolean) {
                    if (!fromUser) return
                    val duration = player?.duration?.takeIf { it > 0L } ?: return
                    val target = duration * value / seekBar.max
                    positionLabel?.text = "${formatTime(target)} / ${formatTime(duration)}"
                }

                override fun onStopTrackingTouch(seekBar: SeekBar) {
                    val exo = player
                    val duration = exo?.duration?.takeIf { it > 0L }
                    if (exo != null && duration != null) {
                        exo.seekTo(duration * seekBar.progress / seekBar.max)
                    }
                    userSeeking = false
                    showControls()
                }
            })
        }
        seekBar = progress
        panel.addView(progress, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(48),
        ))

        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
        }
        panel.addView(row, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            dp(70),
        ))

        fun addButton(label: String, description: String, action: () -> Unit): Button {
            val button = Button(this).apply {
                text = label
                textSize = 19f
                setTextColor(Color.WHITE)
                // Some ECARX Android 4.4 builds omit TextView.setAllCaps despite
                // reporting API 19. Removing the transformation is equivalent
                // and only relies on the original TextView API.
                transformationMethod = null
                minWidth = 0
                minHeight = dp(64)
                contentDescription = description
                background = carButtonBackground(0xFF303030.toInt())
                setOnClickListener {
                    action()
                    showControls()
                }
            }
            row.addView(button, LinearLayout.LayoutParams(0, dp(64), 1f).apply {
                // Avoid the API 17 start/end margin methods on vendor-modified
                // Android 4.4 frameworks; this landscape UI is not RTL.
                setMargins(dp(4), 0, dp(4), 0)
            })
            return button
        }

        addButton("Close", "Close player") { finishWithResult(playbackError) }
        addButton("−${seekBackMs / 1_000}s", "Rewind ${seekBackMs / 1_000} seconds") {
            queueSeek(-seekBackMs)
        }
        playPauseButton = addButton("Pause", "Play or pause") {
            val exo = player
            if (exo?.isPlaying == true) exo.pause() else exo?.play()
            exo?.let(::updateCarControls)
        }
        addButton("+${seekForwardMs / 1_000}s", "Forward ${seekForwardMs / 1_000} seconds") {
            queueSeek(seekForwardMs)
        }
        audioButton = addButton("Audio", "Choose audio language") { showAudioDialog() }
        captionsButton = addButton("CC", "Choose subtitles") { showSubtitleDialog() }
        return panel
    }

    private fun carButtonBackground(color: Int): GradientDrawable = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(8).toFloat()
        setStroke(dp(1), 0xFF707070.toInt())
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density + 0.5f).toInt()

    private fun toggleControls() {
        if (controlPanel?.visibility == View.VISIBLE) {
            controlPanel?.visibility = View.GONE
            timelineHandler.removeCallbacks(hideControlsRunnable)
        } else {
            showControls()
        }
    }

    private fun showControls() {
        controlPanel?.visibility = View.VISIBLE
        timelineHandler.removeCallbacks(hideControlsRunnable)
        if (player?.isPlaying == true) {
            timelineHandler.postDelayed(hideControlsRunnable, 6_000L)
        }
    }

    private fun clearCustomControlReferences() {
        controlPanel = null
        playPauseButton = null
        audioButton = null
        captionsButton = null
        seekBar = null
        positionLabel = null
    }

    private fun describeLinkage(error: LinkageError): String {
        val member = error.message
            ?.replace(Regex("[^A-Za-z0-9_.$()/:;<> -]"), "?")
            ?.take(180)
            .orEmpty()
        return if (member.isBlank()) error.javaClass.simpleName else "${error.javaClass.simpleName}: $member"
    }

    private fun updateCarControls(exo: ExoPlayer) {
        playPauseButton?.text = if (exo.isPlaying) "Pause" else "Play"
        playPauseButton?.contentDescription = if (exo.isPlaying) "Pause video" else "Play video"
        if (userSeeking) return
        val duration = exo.duration.takeIf { it > 0L }
        val position = exo.currentPosition.coerceAtLeast(0L)
        positionLabel?.text = "${formatTime(position)} / ${duration?.let(::formatTime) ?: "--:--"}"
        seekBar?.apply {
            isEnabled = duration != null
            progress = if (duration == null) 0 else ((position * max) / duration).toInt()
        }
    }

    private fun formatTime(milliseconds: Long): String {
        val totalSeconds = milliseconds.coerceAtLeast(0L) / 1_000L
        val hours = totalSeconds / 3_600L
        val minutes = (totalSeconds % 3_600L) / 60L
        val seconds = totalSeconds % 60L
        return if (hours > 0L) {
            String.format("%d:%02d:%02d", hours, minutes, seconds)
        } else {
            String.format("%02d:%02d", minutes, seconds)
        }
    }

    private fun audioTracks(): List<NativeAudioTrack> {
        val selector = trackSelector ?: return emptyList()
        val mapped = selector.currentMappedTrackInfo ?: return emptyList()
        val result = mutableListOf<NativeAudioTrack>()
        for (rendererIndex in 0 until mapped.rendererCount) {
            if (mapped.getRendererType(rendererIndex) != C.TRACK_TYPE_AUDIO) continue
            val groups = mapped.getTrackGroups(rendererIndex)
            for (groupIndex in 0 until groups.length) {
                val group = groups[groupIndex]
                for (trackIndex in 0 until group.length) {
                    val format = group.getFormat(trackIndex)
                    val fields = listOfNotNull(
                        format.label?.takeIf { it.isNotBlank() },
                        format.language?.takeIf { it.isNotBlank() },
                        format.sampleMimeType?.substringAfterLast('/')?.uppercase(),
                        format.channelCount.takeIf { it > 0 }?.let { "${it}ch" },
                    ).distinct()
                    val label = fields.joinToString(" • ").ifBlank { "Audio ${result.size + 1}" }
                    result += NativeAudioTrack(
                        rendererIndex = rendererIndex,
                        groupIndex = groupIndex,
                        trackIndex = trackIndex,
                        label = label,
                        candidate = MediaTrackCandidate(
                            id = format.id,
                            language = format.language,
                            label = format.label,
                            codec = format.sampleMimeType ?: format.codecs,
                            ordinal = result.size,
                        ),
                    )
                }
            }
        }
        return result
    }

    private fun applyRequestedAudio() {
        val tracks = audioTracks()
        val index = MediaTrackSelectionPolicy.bestIndex(
            tracks.map { it.candidate },
            requestedAudioId,
            requestedAudioLanguage,
            requestedAudioTitle,
            requestedAudioCodec,
            requestedOrdinal = plexAudioIds.indexOf(requestedAudioId).takeIf { it >= 0 },
        ) ?: return
        applyAudio(tracks[index])
    }

    @Suppress("DEPRECATION")
    private fun applyAudio(track: NativeAudioTrack) {
        val selector = trackSelector ?: return
        val mapped = selector.currentMappedTrackInfo ?: return
        require(isCurrent(mapped, track.rendererIndex, track.groupIndex, track.trackIndex)) {
            "Audio track list changed"
        }
        val builder = selector.buildUponParameters()
            .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
        for (rendererIndex in 0 until mapped.rendererCount) {
            if (mapped.getRendererType(rendererIndex) == C.TRACK_TYPE_AUDIO) {
                builder.clearSelectionOverrides(rendererIndex)
            }
        }
        builder.setSelectionOverride(
            track.rendererIndex,
            mapped.getTrackGroups(track.rendererIndex),
            DefaultTrackSelector.SelectionOverride(track.groupIndex, track.trackIndex),
        )
        selector.parameters = builder.build()
        activeAudio = track
        diagnostics.add("Audio active: ${track.label}")
        updateAudioButton()
    }

    private fun isCurrent(
        mapped: com.google.android.exoplayer2.trackselection.MappingTrackSelector.MappedTrackInfo,
        rendererIndex: Int,
        groupIndex: Int,
        trackIndex: Int,
    ): Boolean {
        if (rendererIndex >= mapped.rendererCount) return false
        val groups = mapped.getTrackGroups(rendererIndex)
        return groupIndex < groups.length && trackIndex < groups[groupIndex].length
    }

    /**
     * Reads what ExoPlayer actually selected, so the Audio and CC buttons stay
     * truthful when a track was chosen by language preference or a default flag
     * rather than by an exact match.
     */
    private fun syncActiveTracks(tracks: Tracks) {
        val mapped = trackSelector?.currentMappedTrackInfo
        if (mapped != null) {
            fun isSelected(type: Int, rendererIndex: Int, groupIndex: Int, trackIndex: Int): Boolean {
                if (!isCurrent(mapped, rendererIndex, groupIndex, trackIndex)) return false
                val trackGroup = mapped.getTrackGroups(rendererIndex)[groupIndex]
                return tracks.groups.any { group ->
                    group.type == type && group.mediaTrackGroup == trackGroup &&
                        group.isTrackSelected(trackIndex)
                }
            }
            activeAudio = audioTracks().firstOrNull {
                isSelected(C.TRACK_TYPE_AUDIO, it.rendererIndex, it.groupIndex, it.trackIndex)
            } ?: activeAudio
            activeSubtitle = subtitleTracks().firstOrNull {
                isSelected(C.TRACK_TYPE_TEXT, it.rendererIndex, it.groupIndex, it.trackIndex)
            }
        }
        updateAudioButton()
        updateCaptionsButton()
    }

    private fun updateAudioButton() {
        val language = activeAudio?.candidate?.language?.uppercase()
        audioButton?.text = language?.takeIf { it.length <= 4 } ?: "Audio"
    }

    private fun showAudioDialog() {
        val tracks = audioTracks()
        if (tracks.isEmpty()) {
            Toast.makeText(this, "No selectable audio tracks", Toast.LENGTH_SHORT).show()
            return
        }
        val selected = activeAudio?.let { active ->
            tracks.indexOfFirst {
                it.rendererIndex == active.rendererIndex &&
                    it.groupIndex == active.groupIndex &&
                    it.trackIndex == active.trackIndex
            }.takeIf { it >= 0 }
        } ?: 0
        val adapter = largeChoiceAdapter(tracks.map { it.label })
        AlertDialog.Builder(this)
            .setTitle("Audio language")
            .setSingleChoiceItems(adapter, selected) { dialog, choice ->
                try {
                    val track = tracks[choice]
                    applyAudio(track)
                    userAudioChoice = track
                } catch (error: LinkageError) {
                    diagnostics.add("Audio switch unavailable: ${describeLinkage(error)}")
                    Toast.makeText(this, "Audio switch is unavailable on this firmware", Toast.LENGTH_LONG).show()
                } catch (error: RuntimeException) {
                    diagnostics.add("Audio switch failed: ${PlaybackDiagnostics.describe(error)}")
                    Toast.makeText(this, "Audio tracks changed; open Audio again", Toast.LENGTH_LONG).show()
                }
                dialog.dismiss()
                showControls()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun isSideloadedSubtitle(candidate: MediaTrackCandidate): Boolean =
        sideloadedSubtitleId != null && candidate.id == sideloadedSubtitleId

    private fun subtitleTracks(): List<NativeSubtitleTrack> {
        val selector = trackSelector ?: return emptyList()
        val mapped = selector.currentMappedTrackInfo ?: return emptyList()
        val result = mutableListOf<NativeSubtitleTrack>()
        var embeddedCount = 0
        for (rendererIndex in 0 until mapped.rendererCount) {
            if (mapped.getRendererType(rendererIndex) != C.TRACK_TYPE_TEXT) continue
            val groups = mapped.getTrackGroups(rendererIndex)
            for (groupIndex in 0 until groups.length) {
                val group = groups[groupIndex]
                for (trackIndex in 0 until group.length) {
                    val format = group.getFormat(trackIndex)
                    val label = format.label?.takeIf { it.isNotBlank() }
                        ?: format.language?.takeIf { it.isNotBlank() }
                        ?: "Subtitle ${result.size + 1}"
                    val sideloaded = sideloadedSubtitleId != null && format.id == sideloadedSubtitleId
                    result += NativeSubtitleTrack(
                        rendererIndex = rendererIndex,
                        groupIndex = groupIndex,
                        trackIndex = trackIndex,
                        label = label,
                        candidate = MediaTrackCandidate(
                            id = format.id,
                            language = format.language,
                            label = format.label,
                            codec = format.sampleMimeType ?: format.codecs,
                            ordinal = if (sideloaded) null else embeddedCount++,
                        ),
                    )
                }
            }
        }
        return result
    }

    private fun applyRequestedSubtitle() {
        val tracks = subtitleTracks()
        val index = MediaTrackSelectionPolicy.bestIndex(
            tracks.map { it.candidate },
            requestedSubtitleId,
            requestedSubtitleLanguage,
            requestedSubtitleTitle,
            requestedSubtitleCodec,
            requestedOrdinal = plexSubtitleIds.indexOf(requestedSubtitleId).takeIf { it >= 0 },
        ) ?: return
        applySubtitle(tracks[index])
    }

    @Suppress("DEPRECATION")
    private fun applySubtitle(track: NativeSubtitleTrack) {
        val selector = trackSelector ?: return
        val mapped = selector.currentMappedTrackInfo ?: return
        require(isCurrent(mapped, track.rendererIndex, track.groupIndex, track.trackIndex)) {
            "Subtitle track list changed"
        }
        val builder = selector.buildUponParameters()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .setSelectUndeterminedTextLanguage(true)
        for (rendererIndex in 0 until mapped.rendererCount) {
            if (mapped.getRendererType(rendererIndex) == C.TRACK_TYPE_TEXT) {
                builder.clearSelectionOverrides(rendererIndex)
            }
        }
        builder.setSelectionOverride(
            track.rendererIndex,
            mapped.getTrackGroups(track.rendererIndex),
            DefaultTrackSelector.SelectionOverride(track.groupIndex, track.trackIndex),
        )
        selector.parameters = builder.build()
        activeSubtitle = track
        diagnostics.add("Subtitle active: ${track.label}")
        updateCaptionsButton()
    }

    @Suppress("DEPRECATION")
    private fun disableSubtitles() {
        val selector = trackSelector ?: return
        val mapped = selector.currentMappedTrackInfo
        val builder = selector.buildUponParameters()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        if (mapped != null) {
            for (rendererIndex in 0 until mapped.rendererCount) {
                if (mapped.getRendererType(rendererIndex) == C.TRACK_TYPE_TEXT) {
                    builder.clearSelectionOverrides(rendererIndex)
                }
            }
        }
        selector.parameters = builder.build()
        activeSubtitle = null
        diagnostics.add("Subtitle active: off")
        updateCaptionsButton()
    }

    private fun updateCaptionsButton() {
        captionsButton?.text = if (activeSubtitle == null) "CC Off" else "CC On"
    }

    private fun largeChoiceAdapter(labels: List<String>): ArrayAdapter<String> =
        object : ArrayAdapter<String>(
            this,
            android.R.layout.simple_list_item_single_choice,
            labels,
        ) {
            override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
                return (super.getView(position, convertView, parent) as TextView).apply {
                    minHeight = dp(64)
                    textSize = 20f
                    gravity = Gravity.CENTER_VERTICAL
                    setPadding(dp(22), 0, dp(22), 0)
                }
            }
        }

    private fun showSubtitleDialog() {
        val tracks = subtitleTracks()
        if (tracks.isEmpty()) {
            Toast.makeText(this, "No playable subtitle tracks", Toast.LENGTH_SHORT).show()
            return
        }
        val labels = listOf("Off") + tracks.map { it.label }
        val selected = activeSubtitle?.let { active ->
            tracks.indexOfFirst {
                it.rendererIndex == active.rendererIndex &&
                    it.groupIndex == active.groupIndex &&
                    it.trackIndex == active.trackIndex
            }.takeIf { it >= 0 }?.plus(1)
        } ?: 0
        val adapter = largeChoiceAdapter(labels)
        AlertDialog.Builder(this)
            .setTitle("Subtitles")
            .setSingleChoiceItems(adapter, selected) { dialog, choice ->
                try {
                    if (choice == 0) {
                        disableSubtitles()
                        userSubtitleChoice = null
                    } else {
                        val track = tracks[choice - 1]
                        applySubtitle(track)
                        userSubtitleChoice = track
                    }
                    userChangedSubtitle = true
                } catch (error: LinkageError) {
                    diagnostics.add("Subtitle switch unavailable: ${describeLinkage(error)}")
                    Toast.makeText(this, "Subtitle switch is unavailable on this firmware", Toast.LENGTH_LONG).show()
                } catch (error: RuntimeException) {
                    diagnostics.add("Subtitle switch failed: ${PlaybackDiagnostics.describe(error)}")
                    Toast.makeText(this, "Subtitle tracks changed; open CC again", Toast.LENGTH_LONG).show()
                }
                dialog.dismiss()
                showControls()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun resetReconnectBudgetIfStable(exo: ExoPlayer, now: Long) {
        // Reconnect retries are for each dropout, not for the whole video: after
        // 30 seconds of steady playback a later mobile-data drop gets 2 fresh tries.
        if (automaticRetries == 0 || recoveredAtMs == 0L) return
        if (exo.playbackState != Player.STATE_READY) return
        if (now - recoveredAtMs < 30_000L) return
        diagnostics.add("Player: connection stable again; reconnect retries reset")
        automaticRetries = 0
        recoveredAtMs = 0L
    }

    /** Returns the Plex stream ID for a track chosen inside the player, if known. */
    private fun plexIdForAudio(track: NativeAudioTrack): String? =
        MediaTrackSelectionPolicy.plexTrackId(track.candidate, plexAudioIds, audioTracks().size)

    private fun plexIdForSubtitle(track: NativeSubtitleTrack): String? {
        if (isSideloadedSubtitle(track.candidate)) return requestedSubtitleId.takeIf { it.isNotBlank() }
        val embedded = subtitleTracks().count { !isSideloadedSubtitle(it.candidate) }
        return MediaTrackSelectionPolicy.plexTrackId(track.candidate, plexSubtitleIds, embedded)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUi()
    }

    @Suppress("DEPRECATION")
    private fun hideSystemUi() {
        window.decorView.systemUiVisibility = (
            View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
    }

    override fun onBackPressed() {
        finishWithResult(playbackError)
    }

    override fun onPause() {
        val exo = player
        activityPaused = true
        wasPlayingBeforePause = exo?.isPlaying == true
        if (!completed && wasPlayingBeforePause) exo?.pause()
        showControls()
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        activityPaused = false
        if (!completed && !renderedFirstFrame) {
            val now = SystemClock.elapsedRealtime()
            startupAttemptStartedAtMs = now
            lastStartupProgressAtMs = now
            readyWithoutFrameAtMs = 0L
        }
        if (!completed && wasPlayingBeforePause) player?.play()
        wasPlayingBeforePause = false
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        val exo = player
        when (keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_MEDIA_REWIND -> {
                queueSeek(-seekBackMs)
                showControls()
                return true
            }
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> {
                queueSeek(seekForwardMs)
                showControls()
                return true
            }
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> {
                if (exo?.isPlaying == true) exo.pause() else exo?.play()
                showControls()
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun activeMarker(positionMs: Long): Marker? = markers.firstOrNull {
        positionMs >= it.startMs && positionMs < it.endMs
    }

    private fun queueSeek(deltaMs: Long) {
        val exo = player ?: return
        val base = pendingSeekPositionMs ?: exo.currentPosition
        val maximum = exo.duration.takeIf { it > 0L } ?: Long.MAX_VALUE
        pendingSeekPositionMs = (base + deltaMs).coerceIn(0L, maximum)
        timelineHandler.removeCallbacks(seekRunnable)
        timelineHandler.postDelayed(seekRunnable, 120L)
    }

    private fun checkStartupProgress(exo: ExoPlayer, now: Long) {
        if (renderedFirstFrame || completed || activityPaused) return

        val buffered = exo.bufferedPosition.coerceAtLeast(0L)
        if (buffered >= lastBufferedPositionMs + 250L) {
            lastBufferedPositionMs = buffered
            lastStartupProgressAtMs = now
        }

        val playerReady = exo.playbackState == Player.STATE_READY
        val hasVideoFormat = exo.videoFormat != null
        if (playerReady && hasVideoFormat) {
            if (readyWithoutFrameAtMs == 0L) readyWithoutFrameAtMs = now
        } else {
            readyWithoutFrameAtMs = 0L
        }

        when (PlaybackStartupWatchdog.evaluate(
            nowMs = now,
            attemptStartedAtMs = startupAttemptStartedAtMs,
            lastProgressAtMs = lastStartupProgressAtMs,
            readyWithoutFrameAtMs = readyWithoutFrameAtMs,
            hardTimeoutMs = startupHardTimeoutMs,
            playerReady = playerReady,
            hasVideoFormat = hasVideoFormat,
        )) {
            PlaybackStartupWatchdog.Reason.READY_WITHOUT_FRAME -> {
                failureKind = "startup_timeout"
                diagnostics.add("Player: ready for 10 seconds but rendered no video frame")
                finishWithResult("RENDER_TIMEOUT: player ready but no video frame within 10 seconds")
            }
            PlaybackStartupWatchdog.Reason.STALLED -> {
                failureKind = "startup_timeout"
                diagnostics.add("Player: no buffer or network progress for 30 seconds")
                diagnostics.add("Startup network: ${formatNetworkBytes(startupNetworkBytes.get())}")
                finishWithResult("STARTUP_STALLED: no loading progress for 30 seconds")
            }
            PlaybackStartupWatchdog.Reason.HARD_LIMIT -> {
                failureKind = "startup_timeout"
                val seconds = startupHardTimeoutMs / 1_000L
                diagnostics.add("Player: startup reached the $seconds-second safety limit")
                diagnostics.add("Startup network: ${formatNetworkBytes(startupNetworkBytes.get())}")
                finishWithResult("STARTUP_TIMEOUT: no video frame within $seconds seconds")
            }
            null -> Unit
        }
    }

    private fun updateSkipButton(positionMs: Long) {
        val markerIndex = markers.indexOfFirst {
            positionMs >= it.startMs && positionMs < it.endMs
        }
        val marker = markers.getOrNull(markerIndex)
        if (skipMode == "automatic" && marker != null && skippedMarkerIndexes.add(markerIndex)) {
            diagnostics.add("Player: automatically skipped ${marker.type}")
            player?.seekTo(marker.endMs)
        }
        skipButton?.apply {
            text = when (marker?.type?.lowercase()) {
                "intro" -> "Skip intro"
                "credits" -> "Skip credits"
                else -> "Skip"
            }
            visibility = if (skipMode == "button" && marker != null) View.VISIBLE else View.GONE
        }
    }

    private fun describeVideoFormat(format: Format?): String? {
        if (format == null) return null
        val size = if (format.width > 0 && format.height > 0) "${format.width}x${format.height}" else "unknown size"
        val codec = format.codecs ?: format.sampleMimeType ?: "unknown codec"
        return "$size / $codec"
    }

    private fun formatNetworkBytes(bytes: Long): String = when {
        bytes >= 1024L * 1024L -> "${bytes / (1024L * 1024L)} MiB"
        bytes >= 1024L -> "${bytes / 1024L} KiB"
        else -> "$bytes B"
    }

    private fun finishWithResult(error: String?) {
        if (completed) return
        completed = true
        val exo = player
        val position = exo?.currentPosition ?: intent.getLongExtra(EXTRA_START_MS, 0L)
        val duration = exo?.duration?.takeIf { it > 0L } ?: 0L
        timelineHandler.removeCallbacks(timelineRunnable)
        timelineHandler.removeCallbacks(seekRunnable)
        timelineHandler.removeCallbacks(hideControlsRunnable)
        if (renderedFirstFrame) reportTimeline(position, if (ended) "stopped" else "paused")
        val audioChoice = userAudioChoice
        val audioChoiceId = audioChoice?.let(::plexIdForAudio)
        val subtitleChoice = userSubtitleChoice
        val subtitleChoiceId = when {
            !userChangedSubtitle -> null
            subtitleChoice == null -> "off"
            else -> plexIdForSubtitle(subtitleChoice)
        }
        playerView?.player = null
        player?.release()
        player = null
        releaseHttpClient()
        setResult(Activity.RESULT_OK, Intent().apply {
            putExtra(RESULT_POSITION_MS, position)
            putExtra(RESULT_DURATION_MS, duration)
            putExtra(RESULT_ENDED, ended)
            putExtra(RESULT_ERROR, error)
            putExtra(RESULT_FAILURE_KIND, failureKind)
            putExtra(RESULT_RENDERED_FRAME, renderedFirstFrame)
            putExtra(RESULT_FIRST_FRAME_MS, firstFrameMs)
            putExtra(RESULT_DECODER, decoderName)
            putExtra(RESULT_VIDEO_FORMAT, videoFormat)
            putExtra(RESULT_NETWORK_BYTES, startupNetworkBytes.get())
            putStringArrayListExtra(RESULT_DIAGNOSTICS, diagnostics.snapshot())
            // Tracks the driver picked inside the player, so the app remembers them.
            if (audioChoice != null) {
                putExtra(RESULT_AUDIO_TRACK_ID, audioChoiceId)
                putExtra(RESULT_AUDIO_LANGUAGE, audioChoice.candidate.language)
            }
            if (userChangedSubtitle) {
                putExtra(RESULT_SUBTITLE_TRACK_ID, subtitleChoiceId)
                putExtra(RESULT_SUBTITLE_LANGUAGE, subtitleChoice?.candidate?.language ?: "off")
            }
        })
        finish()
    }

    override fun onDestroy() {
        timelineHandler.removeCallbacks(timelineRunnable)
        timelineHandler.removeCallbacks(seekRunnable)
        timelineHandler.removeCallbacks(hideControlsRunnable)
        playerView?.player = null
        player?.release()
        player = null
        releaseHttpClient()
        super.onDestroy()
    }

    private fun releaseHttpClient() {
        val client = playbackHttpClient ?: return
        playbackHttpClient = null
        client.dispatcher().cancelAll()
        client.connectionPool().evictAll()
        client.dispatcher().executorService().shutdown()
    }

    private fun reportTimeline(positionMs: Long, state: String) {
        if (!timelineUrl.startsWith("https://") || ratingKey.isBlank()) return
        val target = Uri.parse(timelineUrl).buildUpon()
            .appendQueryParameter("ratingKey", ratingKey)
            .appendQueryParameter("key", "/library/metadata/$ratingKey")
            .appendQueryParameter("state", state)
            .appendQueryParameter("time", positionMs.toString())
            .appendQueryParameter("duration", mediaDurationMs.toString())
            .build().toString()
        val client = playbackHttpClient ?: return
        Thread {
            try {
                val builder = Request.Builder().url(target)
                for ((key, value) in requestHeaders) builder.header(key, value)
                if (sessionId.isNotBlank()) builder.header("X-Plex-Session-Identifier", sessionId)
                client.newCall(builder.build()).execute().use { response -> response.code() }
            } catch (_: Exception) {
                // Dart-side bounded diagnostics records the final progress failure if needed.
            }
        }.start()
    }

    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_TITLE = "title"
        const val EXTRA_START_MS = "startMs"
        const val EXTRA_HEADERS_KEYS = "headerKeys"
        const val EXTRA_HEADERS_VALUES = "headerValues"
        const val EXTRA_RATING_KEY = "ratingKey"
        const val EXTRA_DURATION_MS = "durationMs"
        const val EXTRA_TIMELINE_URL = "timelineUrl"
        const val EXTRA_SESSION_ID = "sessionId"
        const val EXTRA_AUDIO_LANGUAGE = "audioLanguage"
        const val EXTRA_SUBTITLE_LANGUAGE = "subtitleLanguage"
        const val EXTRA_AUDIO_TRACK_ID = "audioTrackId"
        const val EXTRA_AUDIO_TITLE = "audioTitle"
        const val EXTRA_AUDIO_CODEC = "audioCodec"
        const val EXTRA_SUBTITLE_TRACK_ID = "subtitleTrackId"
        const val EXTRA_SUBTITLE_URL = "subtitleUrl"
        const val EXTRA_SUBTITLE_TITLE = "subtitleTitle"
        const val EXTRA_SUBTITLE_CODEC = "subtitleCodec"
        const val EXTRA_AUDIO_TRACK_IDS = "audioTrackIds"
        const val EXTRA_SUBTITLE_TRACK_IDS = "subtitleTrackIds"
        const val EXTRA_SKIP_MODE = "skipMode"
        const val EXTRA_STARTUP_HARD_TIMEOUT_MS = "startupHardTimeoutMs"
        const val EXTRA_SEEK_BACK_MS = "seekBackMs"
        const val EXTRA_SEEK_FORWARD_MS = "seekForwardMs"
        const val EXTRA_MARKER_TYPES = "markerTypes"
        const val EXTRA_MARKER_STARTS = "markerStarts"
        const val EXTRA_MARKER_ENDS = "markerEnds"
        const val RESULT_POSITION_MS = "positionMs"
        const val RESULT_DURATION_MS = "durationMs"
        const val RESULT_ENDED = "ended"
        const val RESULT_ERROR = "error"
        const val RESULT_FAILURE_KIND = "failureKind"
        const val RESULT_RENDERED_FRAME = "renderedFrame"
        const val RESULT_FIRST_FRAME_MS = "firstFrameMs"
        const val RESULT_DECODER = "decoder"
        const val RESULT_VIDEO_FORMAT = "videoFormat"
        const val RESULT_NETWORK_BYTES = "networkBytes"
        const val RESULT_DIAGNOSTICS = "diagnostics"
        const val RESULT_AUDIO_TRACK_ID = "audioTrackId"
        const val RESULT_AUDIO_LANGUAGE = "audioLanguage"
        const val RESULT_SUBTITLE_TRACK_ID = "subtitleTrackId"
        const val RESULT_SUBTITLE_LANGUAGE = "subtitleLanguage"
    }
}
