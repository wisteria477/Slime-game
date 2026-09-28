# Slime Life — 100-item Live Mode / Sims-comparison implementation pass

This maps the user's 100-item UI/presentation critique to the current Godot implementation. "Addressed" means there is an actual code path or playable prototype treatment. Items that fundamentally require final art/animation asset production are marked as foundation implemented rather than pretending the finished asset library already exists.

1. Active slime identity — addressed by bottom active-slime card.
2. Slime portrait identity — addressed by color-coded slime family dots; final portrait renders remain an art upgrade.
3. Selected slime clarity — selected family dot + in-world selection disc.
4. Oversized household bar — compacted and dynamically sized.
5. Household scaling — width scales with member count.
6. Ambiguous plus — Add Slime tooltip/compact family control.
7. Baby state — heart control remains clickable and explains requirements.
8. Emotion indicator — active card changes color and names current emotion.
9. Current action — visible in active card and action strip.
10. Action queue — explicit player queue is visible.
11. Cancel action — current action is cancellable from queue/context.
12. Manual queueing — world interactions append to player queue.
13. Long-action progress — action progress bar + in-world percentage.
14. Floating debug info — reduced to deliberate currency display.
15. Currency treatment — puddle-coin indicator.
16. Bills relevance — only surfaced when due.
17. Lot-name clutter — removed from permanent money HUD.
18. Time hierarchy — day/time is its own schedule control.
19. Speed controls — pause/1x/2x/3x controls in active card.
20. Pause visibility — clock explicitly shows PAUSED.
21. Desktop/controller parity — keyboard and gamepad camera/mode/pause controls.
22. Bottom hierarchy — PROFILE / NEEDS are active-slime controls; BUILD is separate mode.
23. VIEW prominence — hidden on portrait-phone layout; selected family controls focus camera.
24. LIFE ambiguity — renamed PROFILE.
25. NEEDS meaning — expandable detailed motive view + urgent motives shown without opening it.
26. BUILD mode identity — Live HUD hides when Build/Buy opens.
27. Live mode identity — active card and contextual world interaction remain exclusive to live mode.
28. Bottom dock organization — compact active card plus dedicated control zones.
29. Bottom-left spacing — phone layout uses non-overlapping controls.
30. BUILD separation — retained as explicit opposite-corner mode switch.
31. Dead lower space — camera framed closer.
32. Camera zoom — phone default zoom tightened.
33. Character-first framing — selecting/family tapping focuses slime.
34. Vertical framing — phone camera target/zoom tuned around house and characters.
35. Lost active slime — creator/load/select focus active slime.
36. Find-my-slime — family controls focus member.
37. Selected marker — in-world selection disc.
38. Thought bubbles — Label3D thought/action feedback.
39. Social feedback — social thought/action text + story notifications.
40. Relationship feedback — friendship/romance transitions emit notifications.
41. Skill feedback — skill-ups emit notifications; actions show progress.
42. In-the-zone presentation — thought bubble, moodlet, activity text.
43. Neglect warning — urgent need text/icons.
44. Hidden-needs problem — critical needs surface while details stay collapsible.
45. Compact status summary — emotion, activity, obligation, urgent state.
46. Contextual world UI — object/slime tap opens contextual interaction menu.
47. Stove choices — Cook Meal interaction.
48. Slime social categories — chat/joke/compliment/hug/flirt/argue context.
49. Interactive-object discoverability — tap marker + context menu.
50. Selected-object state — 3D object selection marker.
51. Interaction UI animation — contextual menu fade-in.
52. Contextual icons — in-world action/need icons.
53. Category language — action icons + Build/Buy categories.
54. Typography readability — enlarged mobile type hierarchy.
55. Type hierarchy — title/profile/status/control sizes separated.
56. Color hierarchy — emotion-driven active-card colors and stronger selected states.
57. Button feedback — normal/hover/pressed/selected visual states.
58. Disabled-state ambiguity — baby control remains actionable and explains why it cannot proceed.
59. Rounded-rectangle sameness — asymmetric slime-button shapes.
60. Slime Life visual language — puddle-shaped panels, slime family dots, emotion colors.
61. HUD character — jelly/puddle styling instead of generic debug chrome.
62. Transition polish — overlays/context menus fade in.
63. Notification area — stacked transient life-event notifications.
64. Aspirations/wants — organized in Profile > Overview.
65. Career visibility — obligation appears on active card; details in Growth.
66. Skills visibility — dedicated Growth section.
67. Relationships visibility — dedicated Social section.
68. Inventory access — Household/Profile data section.
69. Aspirations/rewards — Overview/Growth surfaces them.
70. Schedule/calendar — tapping day/time opens current schedule and bills/event data.
71. Secondary actions — moved away from live HUD into Profile/Settings.
72. Common vs rare systems — Live HUD only holds daily-play controls.
73. Settings/debug separation — audio, mortality, save/share/cheats moved to Settings overlay.
74. Environment blockout — foundation improved with richer procedural room objects.
75. Furniture silhouettes — furniture forms rebuilt with recognizable details.
76. Room personality — starter house gets decor, rug, plant, lighting and hobby pieces.
77. Kitchen/bathroom readability — stove/fridge/counter and bath/shower/toilet/sink/mirror sets.
78. Decor/clutter — rug, plant, lamp, dresser, wall art and books.
79. Lighting — functional local lamp lights + day/night sun.
80. Lot-edge presentation — world ground extends beyond lot.
81. Neighborhood context — road, sidewalk, front path and trees.
82. Blue-void dominance — surrounding ground fills camera context.
83. Cutaway behavior — exterior wall hiding follows camera yaw.
84. Architecture readability — doors have panels/knobs; windows have glass/frames/crossbars.
85. Material variation — glass/metal/emissive/jelly/wood-like procedural materials established; final authored material library remains an asset task.
86. Interactive/decor distinction — functional objects respond to contextual taps; decor does not expose irrelevant actions.
87. Tap feedback — selection marker + contextual menu.
88. Autonomy visibility — autonomous current action and thought bubble.
89. Ordered vs autonomous distinction — player commands appear in explicit manual queue.
90. Engrossment storytelling — In the Zone, project progress, urgent interruption and moodlets.
91. Personality communication — profile, habits, preferred hobby, wants and autonomous behavior.
92. Emergencies — critical motive icons/text and moodlets.
93. State memory burden — active card, queue, thought bubble, obligations and notifications externalize state.
94. Onboarding — guided first-slime tutorial for selection, object interaction, social interaction, Profile/Needs/Build.
95. Pause/options — dedicated speed controls + Settings gear.
96. Floor/build-level controls — Build header includes level cycling.
97. Coherent Build toolset — Build/Buy mode has categories, search, prices, rotate, palette, undo/redo, level, Done.
98. Mobile thumb layout — primary live buttons kept low; camera-only secondary control hidden on portrait phones.
99. Bottom-corner use — Profile/Needs left, Build right, active card central.
100. Storytelling — skill-ups, aging, projects, bills, promotions, relationships, social milestones, critical needs and current autonomous decisions are surfaced as play events.

## QA gate

The project now includes ci/life_loop_smoke.gd and the runtime workflow runs it after Godot import/boot. It exercises a starter home, reachable bed/stove/toilet/bathing/hobby objects, two adults, queued cooking, relationships, a baby, serialization, room detection, home value and world ticking.

## Asset honesty

The code/prototype treatment exists for all 100 items above. Final AAA-quality furniture meshes, bespoke character animation clips, final icon art, authored materials, voice/sound libraries and large content quantities still require actual production assets; this tracker does not mislabel those asset-production tasks as already finished.
