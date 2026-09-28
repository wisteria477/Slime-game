class_name SlimeAudio
extends Node

var music_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer
var ui_player: AudioStreamPlayer
var music_enabled := true
var sfx_enabled := true
var music_volume_db := -24.0
var sfx_volume_db := -10.0

func _ready() -> void:
    music_player = AudioStreamPlayer.new()
    music_player.name = "Music"
    music_player.volume_db = music_volume_db
    add_child(music_player)

    sfx_player = AudioStreamPlayer.new()
    sfx_player.name = "SFX"
    sfx_player.volume_db = sfx_volume_db
    add_child(sfx_player)

    ui_player = AudioStreamPlayer.new()
    ui_player.name = "UI"
    ui_player.volume_db = -13.0
    add_child(ui_player)

    music_player.stream = _make_ambient_loop()
    if music_enabled:
        music_player.play()

func set_music_enabled(enabled: bool) -> void:
    music_enabled = enabled
    if music_player == null:
        return
    if enabled:
        if not music_player.playing:
            music_player.play()
    else:
        music_player.stop()

func set_sfx_enabled(enabled: bool) -> void:
    sfx_enabled = enabled

func ui_click() -> void:
    if not sfx_enabled or ui_player == null:
        return
    ui_player.stream = _make_chime([520.0, 660.0], 0.055, 0.16)
    ui_player.play()

func positive() -> void:
    if not sfx_enabled or sfx_player == null:
        return
    sfx_player.stream = _make_chime([440.0, 660.0, 880.0], 0.075, 0.22)
    sfx_player.play()

func social() -> void:
    if not sfx_enabled or sfx_player == null:
        return
    sfx_player.stream = _make_chime([620.0, 720.0, 640.0], 0.06, 0.18)
    sfx_player.play()

func baby() -> void:
    if not sfx_enabled or sfx_player == null:
        return
    sfx_player.stream = _make_chime([660.0, 880.0, 990.0, 1100.0], 0.085, 0.20)
    sfx_player.play()

func build_place() -> void:
    if not sfx_enabled or sfx_player == null:
        return
    sfx_player.stream = _make_chime([310.0, 380.0], 0.045, 0.13)
    sfx_player.play()

func warning() -> void:
    if not sfx_enabled or sfx_player == null:
        return
    sfx_player.stream = _make_chime([260.0, 220.0], 0.10, 0.17)
    sfx_player.play()

func _make_chime(frequencies: Array[float], note_seconds: float, amplitude: float) -> AudioStreamWAV:
    var sample_rate := 22050
    var total_seconds := note_seconds * float(frequencies.size())
    var sample_count := maxi(1, int(total_seconds * sample_rate))
    var bytes := PackedByteArray()
    bytes.resize(sample_count * 2)
    var samples_per_note := maxi(1, int(note_seconds * sample_rate))
    for i in range(sample_count):
        var note_index := mini(frequencies.size() - 1, i / samples_per_note)
        var local_index := i % samples_per_note
        var t := float(i) / float(sample_rate)
        var local_progress := float(local_index) / float(samples_per_note)
        var envelope := sin(PI * clampf(local_progress, 0.0, 1.0))
        var value := sin(TAU * frequencies[note_index] * t) * amplitude * envelope
        _write_pcm16(bytes, i, value)
    return _wav(bytes, sample_rate, false)

func _make_ambient_loop() -> AudioStreamWAV:
    var sample_rate := 22050
    var seconds := 8.0
    var sample_count := int(seconds * sample_rate)
    var bytes := PackedByteArray()
    bytes.resize(sample_count * 2)
    var notes: Array[float] = [174.61, 220.0, 261.63, 220.0]
    for i in range(sample_count):
        var t := float(i) / float(sample_rate)
        var chord_index := mini(notes.size() - 1, int(t / 2.0))
        var root := notes[chord_index]
        var shimmer := sin(TAU * root * t) * 0.035
        shimmer += sin(TAU * root * 1.5 * t) * 0.018
        shimmer += sin(TAU * root * 2.0 * t) * 0.010
        var slow_pulse := 0.72 + sin(TAU * 0.125 * t) * 0.18
        _write_pcm16(bytes, i, shimmer * slow_pulse)
    var stream := _wav(bytes, sample_rate, true)
    stream.loop_begin = 0
    stream.loop_end = sample_count
    return stream

func _wav(bytes: PackedByteArray, sample_rate: int, looped: bool) -> AudioStreamWAV:
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = sample_rate
    stream.stereo = false
    stream.data = bytes
    if looped:
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    return stream

func _write_pcm16(bytes: PackedByteArray, sample_index: int, value: float) -> void:
    var scaled := int(clampf(value, -1.0, 1.0) * 32767.0)
    if scaled < 0:
        scaled += 65536
    bytes[sample_index * 2] = scaled & 0xff
    bytes[sample_index * 2 + 1] = (scaled >> 8) & 0xff
