class_name CrewLogs
extends RefCounted
## The crew's logs, read at the terminals in the Cryo Bay. Pure story: nothing here is a rule,
## a number from a puzzle or an answer, and reading them never changes the game.

const CREW: Array[Dictionary] = [
	{"pod": "POD 1", "name": "CAPT. MARA OKAFOR", "suit": Color(0.85, 0.86, 0.95)},
	{"pod": "POD 2", "name": "ENG. ILYA PETROV", "suit": Color(0.95, 0.62, 0.3)},
	{"pod": "POD 3", "name": "DR. SANA RAHMAN", "suit": Color(0.55, 0.85, 0.8)},
	{"pod": "POD 4", "name": "TECH. JOON PARK", "suit": Color(0.75, 0.7, 0.95)},
	{"pod": "POD 5", "name": "PILOT TEO ALVAREZ", "suit": Color(0.95, 0.85, 0.5)},
	{"pod": "POD 6", "name": "COOK ADA NWOSU", "suit": Color(0.6, 0.8, 0.95)},
]

const LOGS: Array[Dictionary] = [
	{
		"title": "LOG 1  ·  CAPT. OKAFOR  ·  DEPARTURE",
		"text": "Day 1 of the long crossing. Six of us, one station, and a very long way from anyone. We take turns on watch while the rest sleep in the cryo bay, so the air and the power are never left alone. The old help system, ORACLE, was bolted into the walls long before us. It does not sleep and it does not complain. I put Joon in the first pod and told him to dream of somewhere warm.",
	},
	{
		"title": "LOG 2  ·  ENG. PETROV  ·  THE REACTOR",
		"text": "The reactor has never liked being pushed. Under a surge the core runs hot, and the coolant has to be set by hand: the display gives the temperature and the state, and the manual gives the sum. Every protocol rewrites the sum a little, so I stopped trusting my memory years ago. Read the display, read the manual, then touch the controls. In that order. Always.",
	},
	{
		"title": "LOG 3  ·  DR. RAHMAN  ·  ABOUT ORACLE",
		"text": "People ask whether ORACLE thinks. It does not. It looks things up in the manuals and shows you the page it found, and it will never press a button for you. I find that comforting. A voice in the dark that only tells you what is written, and shows you where. If it ever sounds sure of something that is not on the page, trust the page.",
	},
	{
		"title": "LOG 4  ·  WATCH ENGINEER  ·  LAST ENTRY",
		"text": "Something hit the station tonight. Power first, then the air, then the comms dish, and the reactor started to climb. Everyone else is asleep and the pods are only holding on a thin trickle of power. I am the one on watch. If you are reading this, the lights are still on, and so is the clock. Fix the station, walk back to the terminal at the far end, and let them sleep.",
	},
]


static func count() -> int:
	return LOGS.size()


static func title(index: int) -> String:
	return LOGS[clampi(index, 0, LOGS.size() - 1)]["title"]


static func text(index: int) -> String:
	return LOGS[clampi(index, 0, LOGS.size() - 1)]["text"]
