class_name SlimeLifeRules
extends RefCounted

const AGE_ORDER := ["baby", "child", "teen", "young_adult", "adult"]
const AGE_DURATIONS := {
    "baby": 240.0,
    "child": 420.0,
    "teen": 540.0,
    "young_adult": 720.0,
}
const SKILLS := ["cooking", "creativity", "logic", "social", "fitness", "handiness", "parenting", "cleaning"]
const CAREERS := {
    "None": {"pay": 0, "skill": "", "start": 0, "end": 0},
    "Gardener": {"pay": 55, "skill": "fitness", "start": 8, "end": 14},
    "Maker": {"pay": 70, "skill": "handiness", "start": 9, "end": 15},
    "Cook": {"pay": 75, "skill": "cooking", "start": 10, "end": 16},
    "Artist": {"pay": 68, "skill": "creativity", "start": 11, "end": 17},
    "Researcher": {"pay": 82, "skill": "logic", "start": 9, "end": 17},
    "Host": {"pay": 62, "skill": "social", "start": 12, "end": 18},
}
const ASPIRATIONS := {
    "Big Happy Puddle": ["Make 3 friends", "Have a baby", "Reach Social 3"],
    "Master Maker": ["Reach Handiness 3", "Repair 3 objects", "Own a workbench"],
    "Cozy Home": ["Keep Comfort high", "Own 5 decorations", "Nap 5 times"],
    "Life of Play": ["Reach Creativity 3", "Play 8 times", "Own 3 toys"],
    "Kitchen Blob": ["Reach Cooking 3", "Cook 6 meals", "Share food"],
    "Bright Mind": ["Reach Logic 3", "Read 5 times", "Complete a project"],
}
const REWARDS := {
    "Calm Core": {"cost": 300, "effect": "slower_need_decay"},
    "Fast Learner": {"cost": 450, "effect": "skill_bonus"},
    "Social Spark": {"cost": 350, "effect": "relationship_bonus"},
    "Neat Gel": {"cost": 350, "effect": "hygiene_bonus"},
}
const SOCIALS := ["Chat", "Joke", "Compliment", "Hug", "Argue", "Apologize", "Flirt", "Kiss", "Propose"]
const EMOTIONS := ["Fine", "Happy", "Playful", "Inspired", "Focused", "Energized", "Sad", "Angry", "Embarrassed", "Uncomfortable", "Tired"]
const WANT_TEMPLATES := [
    {"id":"eat", "text":"Grab something to eat", "need":"hunger"},
    {"id":"sleep", "text":"Get some rest", "need":"energy"},
    {"id":"wash", "text":"Freshen up", "need":"hygiene"},
    {"id":"play", "text":"Do something fun", "need":"fun"},
    {"id":"social", "text":"Talk to another slime", "need":"social"},
    {"id":"cozy", "text":"Get comfortable", "need":"comfort"},
    {"id":"learn", "text":"Practice a skill", "need":""},
]
const FEAR_TEMPLATES := [
    {"id":"lonely", "text":"Being left alone too long"},
    {"id":"mess", "text":"A filthy home"},
    {"id":"failure", "text":"Failing at an important goal"},
    {"id":"conflict", "text":"A relationship falling apart"},
]
const ACHIEVEMENTS := {
    "first_friend": "Made a real friend",
    "first_baby": "Welcomed a baby slime",
    "skill_three": "Reached level 3 in a skill",
    "career_two": "Earned a career promotion",
    "home_value": "Built a valuable home",
    "five_slimes": "Grew the household to five slimes",
}

static func default_skills() -> Dictionary:
    var result := {}
    for skill in SKILLS:
        result[skill] = {"level": 0, "xp": 0.0}
    return result

static func default_aspiration(personality: String) -> String:
    match personality:
        "Foodie":
            return "Kitchen Blob"
        "Playful":
            return "Life of Play"
        "Neat":
            return "Cozy Home"
        "Bubbly":
            return "Big Happy Puddle"
        "Independent":
            return "Bright Mind"
        _:
            return "Cozy Home"

static func random_wants(rng: RandomNumberGenerator, count := 3) -> Array:
    var pool := WANT_TEMPLATES.duplicate(true)
    pool.shuffle()
    return pool.slice(0, mini(count, pool.size()))

static func random_fear(rng: RandomNumberGenerator) -> Dictionary:
    return FEAR_TEMPLATES[rng.randi_range(0, FEAR_TEMPLATES.size() - 1)].duplicate(true)

static func age_index(stage: String) -> int:
    return AGE_ORDER.find(stage)

static func next_age(stage: String) -> String:
    var index := age_index(stage)
    if index < 0 or index >= AGE_ORDER.size() - 1:
        return stage
    return AGE_ORDER[index + 1]
