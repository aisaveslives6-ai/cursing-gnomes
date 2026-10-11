class_name SimKeyboardDict
extends RefCounted
## Cursing Gnomes — custom keyboard dictionary, autocorrect engine, and
## word learning for the phone's built-in keyboard (Jeremy 2026-10-04:
## "give it the best damn learning auto correct to ever exist").
##
## Pure logic — no rendering, no input. The PhoneKeyboard UI calls into this.
##
## What makes it smart:
##   - BASE dictionary: common words + texting slang + game terms (never
##     "corrected", never flagged unknown)
##   - PERSONAL frequency model: every word you type is counted; frequent
##     words are trusted and ranked first
##   - BIGRAM context model: learns which words follow which words, so
##     corrections and suggestions fit the sentence ("attack the dragom"
##     -> "dragon", not "drag on")
##   - CORRECTION MEMORY: if you override a correction, it remembers and
##     never makes that same "correction" again
##   - STYLE ADAPTATION: slang/crude affinity — if you type informal, it
##     stops trying to formalize you
##   - QWERTY-aware edit distance: adjacent-key typos cost less, so
##     "teh"->"the" and "gane"->"game" win over random matches
##   - 4 aggression levels: low / medium / high / aggressive
##   - Unknown-word learning: 3 uses -> "Add word?" prompt (or auto-learn)
##   - Learned words feed suggestions; long-press a learned suggestion
##     to delete it from the custom dictionary
##
## Aggression semantics:
##   low        — suggestions only, never auto-replaces
##   medium     — fixes obvious single-char typos the context supports
##   high       — aggressive correction of likely-intended words (dist 1-2)
##   aggressive — rewrites with confidence, learns fastest from everything

const SAVE_PATH := "user://keyboard_dict.cfg"

# Test isolation: override the save path (tests set this to a temp file).
static var _save_path_override := ""


static func set_save_path_override(path: String) -> void:
	_save_path_override = path


static func _save_path() -> String:
	return _save_path_override if _save_path_override != "" else SAVE_PATH

# How many times an unknown word must be typed before the "Add word?" prompt.
const LEARN_THRESHOLD := 3

const AGGRESSION_LEVELS := ["low", "medium", "high", "aggressive"]

# Persistence caps so the save file stays small.
const MAX_BIGRAMS := 2000
const MAX_WORD_FREQ := 3000

## Autocorrect settings (persisted).
var aggression: String = "medium"
var auto_learn: bool = false  # if true, skip the "Add word?" prompt and learn silently
var kb_theme: String = "dark"  # keyboard visual theme
var auto_space: bool = true  # Jeremy 2026-10-05: auto-insert space after suggestions/punctuation

## Base dictionary: word -> true. Never corrected, never flagged.
var _base_words: Dictionary = {}
## Learned words: word -> true (user-approved additions).
var _learned: Dictionary = {}
## Unknown word usage counts: word -> count (for the "Add word?" trigger).
var _unknown_counts: Dictionary = {}
## The word that most recently triggered a learn prompt (for the UI).
var last_prompt_word := ""
## Personal frequency: word -> times the user typed it. Trust + ranking.
var _word_freq: Dictionary = {}
## Bigram context: "prev|next" -> count.
var _bigrams: Dictionary = {}
## Correction overrides: "typed|correction" -> true. Never repeat these.
var _correction_blacklist: Dictionary = {}
## Style: 0.0 = formal, 1.0 = fully informal/crude. Drives slang ranking
## and suppresses "formalizing" corrections.
var _slang_affinity: float = 0.0
## Running word for bigram chaining (set by note_word_typed).
var _last_word: String = ""
## Jeremy 2026-10-06: suggestions() runs on EVERY keystroke, so the
## candidate pool (learned + base words, ~3000 entries) is cached here
## with a first-character index instead of being rebuilt per call.
## Marked dirty only when the vocabulary actually changes.
var _cand_pool: Array = []
var _cand_by_first: Dictionary = {}
var _cand_dirty: bool = true

# QWERTY adjacency for typo-aware edit distance.
const QWERTY_ROWS := ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

# Informal markers: typing these raises slang affinity.
const SLANG_MARKERS := [
	"lol", "lmao", "rofl", "brb", "tbh", "imo", "idk", "nvm", "smh", "wtf",
	"omg", "omw", "ttyl", "gtg", "np", "thx", "pls", "plz", "u", "ur", "r",
	"yea", "ye", "nah", "yep", "nope", "gonna", "wanna", "gotta", "y'all",
	"ain't", "damn", "hell", "shit", "fuck", "fucking", "bitch", "ass",
	"crap", "piss", "dumbass", "bastard",
]

# --- base vocabulary ----------------------------------------------------------
const BASE_WORDS := [
	# articles / prepositions / conjunctions (the glue of English)
	"the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "at",
	"for", "with", "by", "from", "as", "into", "out", "about", "after",
	"over", "under", "between", "through", "during", "before", "above",
	"below", "up", "down", "off", "around",
	# pronouns / common
	"i", "you", "he", "she", "we", "they", "it", "me", "him", "her", "us",
	"them", "my", "your", "his", "our", "their", "mine", "yours", "this",
	"that", "these", "those", "what", "when", "where", "who", "why", "how",
	"which", "there", "here", "then", "than", "one", "two", "all", "more",
	"most", "some", "any", "many", "much", "few", "other", "such", "only",
	"own", "same", "so", "words",
	# verbs
	"am", "is", "are", "was", "were", "be", "been", "being", "have", "has",
	"had", "do", "does", "did", "done", "will", "would", "can", "could",
	"should", "shall", "may", "might", "must", "go", "going", "went", "gone",
	"come", "came", "coming", "see", "saw", "seen", "know", "knew", "known",
	"think", "thought", "say", "said", "tell", "told", "ask", "asked", "give",
	"gave", "given", "take", "took", "taken", "make", "made", "want",
	"wanted", "need", "needed", "like", "liked", "love", "loved", "hate",
	"hated", "get", "got", "gotten", "let", "help", "helped", "try", "tried",
	"work", "worked", "play", "played", "build", "built", "attack",
	"attacked", "defend", "fight", "fought", "win", "won", "lose", "lost",
	"die", "died", "kill", "killed", "send", "sent", "read", "write", "wrote",
	"run", "ran", "walk", "talk", "talked", "listen", "look", "looked",
	"find", "found", "keep", "leave", "left", "bring", "buy", "bought",
	"sell", "pay", "paid", "meet", "met", "wait", "stop", "start", "began",
	"begin", "end", "open", "close", "move", "moved", "turn", "put", "set",
	"seem", "feel", "felt", "become", "grow", "hold", "stand", "sit", "lie",
	"laugh", "laughed", "cry", "smile", "shout", "whisper", "warn", "threaten",
	"promise", "swear", "bet", "guess", "hope", "wish", "dream", "remember",
	"forget", "learn", "teach", "train", "hire", "fire", "marry", "divorce",
	# nouns
	"time", "day", "night", "morning", "evening", "people", "man", "woman",
	"men", "women", "kid", "kids", "king", "queen", "lord", "lady", "prince",
	"princess", "war", "peace", "gold", "wood", "food", "seeds", "oil",
	"town", "city", "village", "house", "home", "farm", "mine", "army",
	"soldier", "warrior", "mage", "ranger", "worker", "kingdom", "empire",
	"faction", "ally", "allies", "enemy", "enemies", "battle", "sword",
	"shield", "castle", "wall", "gate", "road", "bridge", "river", "lake",
	"mountain", "forest", "field", "game", "phone", "message", "news",
	"rumor", "rumors", "story", "secret", "plan", "deal", "trade", "money",
	"tax", "taxes", "job", "work", "name", "word", "thing", "stuff", "point",
	"problem", "question", "answer", "idea", "reason", "way", "place",
	"world", "life", "death", "birth", "family", "friend", "friends",
	"brother", "sister", "mother", "father", "son", "daughter", "wife",
	"husband", "baby", "dog", "cat", "horse", "cow", "pig", "chicken",
	"sheep", "wolf", "bear", "deer", "bird", "fish", "tree", "rock",
	"stone", "iron", "steel", "fire", "water", "earth", "air", "ice",
	"light", "dark", "sun", "moon", "star", "stars", "sky", "cloud", "rain",
	"snow", "storm", "wind",
	# adjectives / adverbs
	"good", "bad", "great", "big", "small", "large", "new", "old", "young",
	"hot", "cold", "fast", "slow", "strong", "weak", "rich", "poor",
	"happy", "sad", "angry", "scared", "proud", "funny", "stupid", "smart",
	"cool", "lame", "awesome", "terrible", "amazing", "crazy", "wild",
	"dead", "alive", "beautiful", "ugly", "nice", "mean", "kind", "cruel",
	"brave", "coward", "loyal", "smart", "dumb", "easy", "hard", "tough",
	"ready", "sure", "true", "false", "right", "wrong", "real", "fake",
	"free", "busy", "tired", "hungry", "thirsty", "sick", "healthy",
	"very", "really", "so", "too", "just", "only", "also", "well", "now",
	"today", "tomorrow", "yesterday", "tonight", "soon", "later", "never",
	"always", "sometimes", "often", "rarely", "maybe", "perhaps", "yes",
	"no", "not", "yeah", "nah", "okay", "ok", "hey", "hi", "hello", "bye",
	"thanks", "please", "sorry", "welcome", "congrats",
	# texting slang — known words, never "corrected"
	"lol", "lmao", "rofl", "lolz", "brb", "afk", "tbh", "imo", "imho",
	"fyi", "btw", "idk", "nvm", "smh", "wtf", "omg", "omw", "ttyl", "gtg",
	"np", "thx", "pls", "plz", "u", "ur", "r", "yea", "ye", "yep", "nope",
	"gonna", "wanna", "gotta", "lemme", "gimme", "dunno", "kinda", "sorta",
	"yeet", "sus", "based", "cringe", "rizz", "bussin", "noob", "pog",
	"poggers", "gg", "wp", "gl", "hf", "ffs", "smfh", "lmk", "nbd", "fomo",
	"irl", "nsfw", "tldr", "ama", "dm", "dms", "af", "lowkey", "highkey",
	"fr", "frfr", "ong", "cap", "bet",
	# crude / swears — known words, never "corrected" (Jeremy 2026-10-05)
	"damn", "hell", "shit", "shitty", "fuck", "fucking", "fucked", "fucker",
	"fuckface", "motherfucker", "bitch", "bitches", "bitchy", "ass", "asses",
	"asshole", "assholes", "asshat", "dumbass", "jackass", "butt", "butts",
	"butthead", "dick", "dicks", "dickhead", "prick", "cunt", "wanker",
	"tosser", "douche", "douchebag", "whore", "slut", "piss", "pissed",
	"pissing", "crap", "crappy", "bastard", "bastards", "shithead", "dipshit",
	"boobs", "tits", "titty", "pussy", "cock", "balls", "boner", "horny",
	"sexy", "naked", "nudes", "screw", "screwed", "sucks", "suck", "sucker",
	"sucka", "blow", "blowjob", "handjob", "orgasm", "cum", "jizz", "tit",
	"nipple", "vagina", "penis", "wiener", "fart", "farts", "farted",
	"poop", "poops", "turd", "pee", "peed", "dingleberry",
	# game-flavored (Cursing Gnomes terms)
	"gnome", "gnomes", "ogre", "ogres", "elf", "elves", "human", "humans",
	"undead", "skeleton", "skeletons", "zombie", "zombies", "ghoul",
	"wraith", "lich", "necromancer", "moose", "thicc", "squabble",
	"gazette", "disaster", "disasters", "tornado", "volcano", "dragon",
	"dragons", "goblin", "goblins", "raid", "raids", "siege", "tribute",
	"treaty", "alliance", "diplomacy", "diplomat", "ruler", "advisor",
	"advisors", "mayor", "commander", "barracks", "foundry", "artillery",
	"nuke", "nukes", "guild", "guildmaster", "tavern", "market", "blacksmith",
	"windmill", "farmhouse", "outhouse", "bathroom", "hall", "throne",
	"crown", "scepter", "banner", "sigil", "crest", "herald", "scout",
	"spy", "spies", "assassin", "medic", "doctor", "priest", "shaman",
	"druid", "paladin", "knight", "archer", "cavalry", "infantry", "militia",
	"garrison", "fort", "fortress", "tower", "keep", "dungeon", "portal",
	"shrine", "temple", "altar", "totem", "plague", "plaguebearer",
	"famine", "drought", "flood", "earthquake", "meteor", "invasion",
	"rebellion", "coup", "election", "council", "senate", "court", "trial",
	"jail", "prison", "bounty", "heist", "smuggle", "bandit", "bandits",
	"pirate", "viking", "samurai", "ninja", "wizard", "witch", "warlock",
	"demon", "angel", "vampire", "werewolf", "giant", "troll", "dwarf",
	"dwarves", "fairy", "pixie", "mermaid", "kraken", "yeti", "phoenix",
	"griffin", "unicorn", "mimic", "slime",
	# contractions
	"don't", "can't", "won't", "isn't", "aren't", "wasn't", "weren't",
	"haven't", "hasn't", "hadn't", "doesn't", "didn't", "wouldn't",
	"couldn't", "shouldn't", "it's", "i'm", "you're", "we're", "they're",
	"that's", "there's", "what's", "let's", "gonna", "wanna", "gotta",
	"y'all", "ain't", "it'll", "we'll", "you'll", "they'll", "i'll",
	"i've", "you've", "we've", "they've",
	# common English (google-10k, deduped against curated above)
	"brothel", "urges", "if", "page", "search", "information", "site", "use", "contact", "business", "web", "view",
	"online", "e", "first", "services", "click", "its", "service", "price", "date", "back", "top", "list",
	"state", "year", "email", "health", "re", "next", "used", "last", "products", "music", "data", "product",
	"system", "post", "add", "policy", "number", "available", "copyright", "support", "best", "software", "jan", "video",
	"info", "rights", "public", "books", "high", "school", "each", "links", "review", "years", "order", "privacy",
	"book", "items", "company", "group", "user", "de", "general", "research", "university", "january", "mail", "full",
	"map", "reviews", "program", "games", "days", "management", "part", "united", "hotel", "item", "international", "center",
	"ebay", "store", "travel", "comments", "development", "report", "member", "details", "line", "terms", "hotels", "type",
	"because", "local", "using", "results", "office", "education", "national", "car", "design", "posted", "internet", "address",
	"community", "within", "states", "area", "shipping", "reserved", "subject", "forum", "long", "code", "show", "o",
	"even", "black", "check", "special", "prices", "website", "index", "sign", "file", "link", "technology", "south",
	"case", "project", "pages", "uk", "version", "section", "sports", "related", "security", "both", "county", "american",
	"photo", "members", "power", "while", "care", "network", "computer", "systems", "three", "total", "following", "download",
	"without", "per", "access", "north", "resources", "current", "posts", "media", "law", "control", "history", "pictures",
	"size", "art", "personal", "since", "including", "guide", "shop", "directory", "board", "location", "change", "white",
	"text", "rating", "rate", "government", "children", "usa", "return", "students", "shopping", "account", "times", "sites",
	"level", "digital", "profile", "previous", "form", "events", "john", "main", "call", "hours", "image", "department",
	"title", "description", "non", "y", "insurance", "another", "property", "class", "still", "quality", "every", "listing",
	"content", "country", "private", "little", "visit", "save", "tools", "low", "reply", "customer", "december", "compare",
	"movies", "include", "college", "value", "article", "york", "card", "jobs", "provide", "source", "author", "different",
	"press", "sale", "print", "course", "canada", "process", "teen", "room", "stock", "training", "credit", "join",
	"science", "categories", "advanced", "west", "sales", "english", "team", "estate", "box", "conditions", "select", "windows",
	"photos", "gay", "thread", "week", "category", "note", "live", "gallery", "table", "register", "however", "june",
	"october", "november", "library", "action", "series", "model", "features", "industry", "provided", "required", "second", "accessories",
	"cost", "movie", "forums", "march", "la", "september", "better", "questions", "july", "yahoo", "medical", "test",
	"dec", "server", "study", "application", "cart", "staff", "articles", "san", "feedback", "again", "looking", "issues",
	"april", "users", "complete", "street", "topic", "comment", "financial", "things", "working", "against", "standard", "person",
	"mobile", "less", "blog", "party", "payment", "equipment", "login", "student", "programs", "offers", "legal", "recent",
	"park", "stores", "side", "act", "red", "memory", "performance", "social", "august", "quote", "language", "options",
	"experience", "rates", "create", "key", "body", "america", "important", "east", "paper", "single", "ii", "age",
	"activities", "club", "example", "girls", "additional", "password", "latest", "something", "gift", "changes", "ca", "texas",
	"oct", "four", "poker", "status", "browse", "issue", "range", "building", "seller", "february", "result", "audio",
	"nov", "offer", "blue", "groups", "al", "files", "event", "release", "analysis", "request", "fax", "china",
	"making", "picture", "needs", "possible", "professional", "yet", "month", "major", "areas", "future", "space", "committee",
	"hand", "cards", "problems", "london", "washington", "meeting", "interest", "id", "child", "enter", "california", "share",
	"similar", "garden", "schools", "million", "added", "reference", "companies", "listed", "learning", "energy", "delivery", "net",
	"popular", "term", "film", "stories", "computers", "journal", "reports", "co", "central", "images", "president", "notice",
	"original", "head", "radio", "until", "cell", "color", "self", "away", "includes", "track", "australia", "discussion",
	"archive", "once", "others", "entertainment", "agreement", "format", "least", "society", "months", "log", "safety", "faq",
	"edition", "cars", "messages", "marketing", "further", "updated", "association", "able", "having", "provides", "david", "fun",
	"already", "green", "studies", "common", "drive", "specific", "several", "feb", "living", "sep", "collection", "called",
	"short", "arts", "lot", "display", "limited", "powered", "solutions", "means", "director", "daily", "beach", "past",
	"natural", "whether", "due", "et", "electronics", "five", "upon", "period", "planning", "database", "says", "official",
	"weather", "mar", "land", "average", "technical", "window", "france", "pro", "region", "island", "record", "direct",
	"microsoft", "conference", "environment", "records", "district", "calendar", "costs", "style", "url", "front", "statement", "update",
	"parts", "aug", "ever", "downloads", "early", "miles", "sound", "resource", "present", "applications", "either", "ago",
	"document", "works", "material", "bill", "apr", "written", "federal", "hosting", "rules", "final", "adult", "tickets",
	"centre", "requirements", "via", "cheap", "finance", "minutes", "else", "mark", "third", "gifts", "europe", "reading",
	"topics", "individual", "tips", "plus", "auto", "cover", "usually", "edit", "together", "videos", "percent", "function",
	"fact", "unit", "getting", "global", "tech", "far", "economic", "en", "player", "projects", "lyrics", "subscribe",
	"submit", "germany", "amount", "watch", "included", "though", "bank", "risk", "everything", "deals", "various", "linux",
	"jul", "production", "commercial", "james", "weight", "heart", "advertising", "received", "choose", "treatment", "newsletter", "archives",
	"points", "knowledge", "magazine", "error", "camera", "jun", "girl", "currently", "construction", "toys", "registered", "clear",
	"golf", "receive", "domain", "methods", "chapter", "makes", "protection", "policies", "loan", "wide", "beauty", "manager",
	"india", "position", "sort", "listings", "models", "michael", "half", "cases", "step", "engineering", "florida", "simple",
	"quick", "none", "wireless", "license", "paul", "friday", "whole", "annual", "published", "basic", "sony", "shows",
	"corporate", "google", "church", "method", "purchase", "customers", "active", "response", "practice", "hardware", "figure", "materials",
	"holiday", "chat", "enough", "designed", "along", "among", "writing", "speed", "countries", "loss", "face", "brand",
	"discount", "higher", "effects", "created", "standards", "bit", "yellow", "political", "increase", "advertise", "base", "near",
	"environmental", "french", "storage", "oh", "japan", "doing", "loans", "shoes", "entry", "stay", "nature", "orders",
	"availability", "africa", "summary", "growth", "notes", "agency", "monday", "european", "activity", "copy", "although", "drug",
	"pics", "western", "income", "force", "cash", "employment", "overall", "bay", "commission", "ad", "package", "contents",
	"players", "engine", "port", "album", "regional", "supplies", "started", "administration", "bar", "institute", "views", "plans",
	"double", "screen", "exchange", "types", "sponsored", "lines", "electronic", "continue", "across", "benefits", "season", "apply",
	"someone", "held", "ny", "anything", "printer", "condition", "effective", "believe", "organization", "effect", "eur", "mind",
	"sunday", "selection", "casino", "tour", "menu", "volume", "cross", "anyone", "mortgage", "silver", "corporation", "inside",
	"solution", "mature", "role", "rather", "weeks", "addition", "supply", "nothing", "certain", "usr", "executive", "running",
	"lower", "necessary", "union", "jewelry", "according", "clothing", "mon", "com", "particular", "fine", "names", "robert",
	"homepage", "hour", "gas", "skills", "six", "bush", "islands", "advice", "career", "military", "rental", "decision",
	"british", "teens", "pre", "huge", "sat", "facilities", "zip", "bid", "sellers", "middle", "cable", "opportunities",
	"taking", "values", "division", "tuesday", "object", "lesbian", "appropriate", "machine", "logo", "length", "actually", "score",
	"statistics", "client", "returns", "capital", "follow", "sample", "investment", "shown", "saturday", "christmas", "england", "culture",
	"band", "flash", "lead", "george", "choice", "starting", "registration", "fri", "thursday", "courses", "consumer", "airport",
	"foreign", "artist", "outside", "furniture", "levels", "channel", "letter", "mode", "phones", "ideas", "wednesday", "structure",
	"fund", "summer", "allow", "degree", "contract", "button", "releases", "wed", "homes", "super", "male", "matter",
	"custom", "virginia", "almost", "located", "multiple", "asian", "distribution", "editor", "inn", "industrial", "cause", "potential",
	"song", "cnet", "los", "focus", "late", "fall", "featured", "rooms", "female", "responsible", "inc", "communications",
	"associated", "thomas", "primary", "cancer", "numbers", "tool", "browser", "spring", "foundation", "voice", "eg", "friendly",
	"schedule", "documents", "communication", "purpose", "feature", "bed", "comes", "police", "everyone", "independent", "ip", "approach",
	"cameras", "brown", "physical", "operating", "hill", "maps", "medicine", "ratings", "chicago", "forms", "glass", "tue",
	"smith", "developed", "thank", "safe", "unique", "survey", "prior", "telephone", "sport", "feed", "animal", "sources",
	"mexico", "population", "pa", "regular", "secure", "navigation", "operations", "therefore", "simply", "evidence", "station", "christian",
	"round", "paypal", "favorite", "understand", "option", "master", "valley", "recently", "probably", "thu", "rentals", "sea",
	"publications", "blood", "cut", "worldwide", "improve", "connection", "publisher", "larger", "anti", "networks", "parents", "nokia",
	"impact", "transfer", "introduction", "kitchen", "tel", "carolina", "wedding", "properties", "hospital", "ground", "overview", "ship",
	"accommodation", "owners", "disease", "excellent", "italy", "perfect", "hair", "opportunity", "kit", "classic", "basis", "command",
	"cities", "william", "express", "award", "distance", "peter", "assessment", "ensure", "thus", "ie", "involved", "el",
	"extra", "especially", "interface", "partners", "budget", "rated", "guides", "success", "maximum", "ma", "operation", "existing",
	"quite", "selected", "boy", "amazon", "patients", "restaurants", "warning", "wine", "locations", "vote", "forward", "flowers",
	"significant", "lists", "technologies", "owner", "retail", "animals", "useful", "directly", "manufacturer", "ways", "est", "providing",
	"rule", "mac", "housing", "takes", "iii", "catalog", "searches", "max", "trying", "authority", "considered", "traffic",
	"programme", "joined", "input", "strategy", "feet", "agent", "valid", "bin", "modern", "senior", "ireland", "teaching",
	"door", "grand", "testing", "charge", "units", "instead", "canadian", "normal", "enterprise", "ships", "entire", "educational",
	"leading", "metal", "positive", "fitness", "chinese", "opinion", "asia", "football", "abstract", "uses", "output", "funds",
	"greater", "likely", "develop", "employees", "artists", "alternative", "processing", "responsibility", "resolution", "java", "guest", "seems",
	"publication", "pass", "relations", "trust", "van", "contains", "session", "multi", "photography", "republic", "fees", "components",
	"vacation", "century", "academic", "assistance", "completed", "skin", "graphics", "indian", "prev", "ads", "mary", "il",
	"expected", "ring", "grade", "dating", "pacific", "organizations", "pop", "filter", "mailing", "vehicle", "longer", "consider",
	"int", "northern", "behind", "panel", "floor", "german", "buying", "match", "proposed", "default", "require", "iraq",
	"boys", "outdoor", "deep", "otherwise", "allows", "rest", "protein", "plant", "reported", "hit", "transportation", "pool",
	"mini", "politics", "partner", "disclaimer", "authors", "boards", "faculty", "parties", "membership", "mission", "eye", "string",
	"sense", "modified", "pack", "released", "stage", "internal", "goods", "recommended", "born", "unless", "richard", "detailed",
	"japanese", "race", "approved", "background", "target", "except", "character", "usb", "maintenance", "ability", "functions", "ed",
	"moving", "brands", "places", "pretty", "trademarks", "phentermine", "spain", "southern", "yourself", "etc", "winter", "battery",
	"youth", "pressure", "submitted", "boston", "debt", "keywords", "medium", "television", "interested", "core", "break", "purposes",
	"throughout", "sets", "dance", "itself", "defined", "papers", "playing", "awards", "fee", "studio", "reader", "virtual",
	"device", "established", "answers", "rent", "las", "remote", "programming", "external", "apple", "le", "regarding", "instructions",
	"min", "offered", "theory", "enjoy", "remove", "aid", "surface", "minimum", "visual", "host", "variety", "teachers",
	"isbn", "martin", "manual", "block", "subjects", "agents", "increased", "repair", "fair", "civil", "understanding", "songs",
	"fixed", "beginning", "hands", "associates", "finally", "az", "updates", "desktop", "classes", "paris", "ohio", "gets",
	"sector", "capacity", "requires", "jersey", "un", "fat", "fully", "electric", "instruments", "quotes", "officer", "driver",
	"businesses", "respect", "unknown", "specified", "restaurant", "mike", "trip", "worth", "mi", "procedures", "teacher", "eyes",
	"relationship", "workers", "georgia", "traditional", "campus", "tom", "showing", "creative", "coast", "benefit", "progress", "funding",
	"devices", "grant", "sub", "agree", "fiction", "hear", "watches", "careers", "beyond", "goes", "families", "led",
	"museum", "themselves", "fan", "transport", "interesting", "blogs", "evaluation", "accepted", "former", "implementation", "ten", "hits",
	"zone", "complex", "galleries", "references", "presented", "jack", "flat", "flow", "agencies", "literature", "respective", "parent",
	"spanish", "michigan", "columbia", "setting", "scale", "economy", "highest", "helpful", "monthly", "critical", "frame", "musical",
	"definition", "secretary", "angeles", "networking", "path", "australian", "employee", "chief", "gives", "bottom", "magazines", "packages",
	"detail", "francisco", "laws", "changed", "pet", "heard", "individuals", "colorado", "royal", "clean", "switch", "russian",
	"largest", "african", "guy", "titles", "relevant", "guidelines", "justice", "connect", "bible", "dev", "cup", "basket",
	"applied", "weekly", "vol", "installation", "described", "demand", "suite", "vegas", "na", "square", "chris", "attention",
	"advance", "skip", "diet", "auction", "gear", "lee", "os", "difference", "allowed", "correct", "charles", "nation",
	"selling", "lots", "piece", "sheet", "firm", "seven", "older", "illinois", "regulations", "elements", "species", "jump",
	"cells", "module", "resort", "facility", "random", "pricing", "certificate", "minister", "motion", "looks", "fashion", "directions",
	"visitors", "documentation", "monitor", "trading", "calls", "whose", "coverage", "couple", "giving", "chance", "vision", "ball",
	"ending", "clients", "actions", "discuss", "accept", "automotive", "goal", "successful", "sold", "communities", "clinical", "situation",
	"sciences", "markets", "lowest", "highly", "publishing", "appear", "emergency", "developing", "lives", "currency", "leather", "determine",
	"temperature", "palm", "announcements", "patient", "actual", "historical", "bob", "commerce", "ringtones", "persons", "difficult", "scientific",
	"satellite", "fit", "tests", "accounts", "amateur", "ex", "pain", "xbox", "particularly", "factors", "coffee", "settings",
	"buyer", "cultural", "steve", "easily", "oral", "ford", "poster", "edge", "functional", "root", "au", "fi",
	"closed", "holidays", "pink", "zealand", "balance", "monitoring", "graduate", "replies", "shot", "architecture", "initial", "label",
	"thinking", "scott", "sec", "recommend", "canon", "league", "waste", "minute", "bus", "provider", "optional", "dictionary",
	"accounting", "manufacturing", "sections", "chair", "fishing", "effort", "phase", "fields", "bag", "fantasy", "po", "letters",
	"motor", "va", "professor", "context", "install", "shirt", "apparel", "generally", "continued", "foot", "mass", "crime",
	"count", "breast", "techniques", "ibm", "johnson", "quickly", "dollars", "websites", "religion", "claim", "driving", "permission",
	"surgery", "patch", "heat", "measures", "generation", "kansas", "miss", "chemical", "task", "reduce", "brought", "himself",
	"nor", "component", "enable", "exercise", "bug", "santa", "mid", "guarantee", "leader", "diamond", "israel", "se",
	"processes", "soft", "servers", "alone", "meetings", "seconds", "jones", "arizona", "keyword", "interests", "flight", "congress",
	"fuel", "username", "produced", "italian", "paperback", "classifieds", "supported", "pocket", "saint", "rose", "freedom", "argument",
	"competition", "creating", "jim", "drugs", "joint", "premium", "providers", "fresh", "characters", "attorney", "upgrade", "di",
	"factor", "growing", "thousands", "stream", "apartments", "pick", "hearing", "eastern", "auctions", "therapy", "entries", "dates",
	"generated", "signed", "upper", "administrative", "serious", "prime", "samsung", "limit", "louis", "steps", "errors", "shops",
	"del", "efforts", "informed", "ga", "ac", "thoughts", "creek", "quantity", "urban", "practices", "sorted", "reporting",
	"essential", "myself", "tours", "platform", "load", "affiliate", "labor", "immediately", "admin", "nursing", "defense", "machines",
	"designated", "tags", "heavy", "covered", "recovery", "joe", "guys", "integrated", "configuration", "merchant", "comprehensive", "expert",
	"universal", "protect", "drop", "solid", "presentation", "languages", "became", "orange", "compliance", "vehicles", "prevent", "theme",
	"im", "campaign", "marine", "improvement", "guitar", "finding", "pennsylvania", "examples", "ipod", "saying", "spirit", "ar",
	"claims", "challenge", "motorola", "acceptance", "strategies", "mo", "affairs", "touch", "intended", "towards", "sa", "goals",
	"suggest", "branch", "charges", "serve", "affiliates", "reasons", "magic", "mount", "talking", "ones", "latin", "multimedia",
	"avoid", "certified", "manage", "corner", "rank", "computing", "oregon", "element", "virus", "abuse", "interactive", "requests",
	"separate", "quarter", "procedure", "leadership", "tables", "define", "racing", "religious", "facts", "breakfast", "kong", "column",
	"plants", "faith", "chain", "developer", "identify", "avenue", "missing", "approximately", "domestic", "sitemap", "recommendations", "houston",
	"reach", "comparison", "mental", "viewed", "moment", "extended", "sequence", "inch", "centers", "opening", "damage", "lab",
	"reserve", "recipes", "gamma", "plastic", "produce", "placed", "truth", "counter", "failure", "follows", "eu", "weekend",
	"dollar", "camp", "ontario", "automatically", "des", "minnesota", "films", "native", "fill", "williams", "movement", "printing",
	"baseball", "owned", "approval", "draft", "chart", "contacts", "jesus", "readers", "clubs", "wa", "jackson", "equal",
	"adventure", "matching", "offering", "shirts", "profit", "leaders", "posters", "institutions", "assistant", "variable", "ave", "advertisement",
	"expect", "parking", "headlines", "compared", "determined", "wholesale", "workshop", "russia", "codes", "kinds", "extension", "seattle",
	"statements", "golden", "completely", "teams", "wi", "lighting", "forces", "gene", "turned", "portable", "electrical", "applicable",
	"disc", "returned", "pattern", "boat", "named", "theatre", "laser", "earlier", "manufacturers", "sponsor", "classical", "icon",
	"warranty", "dedicated", "indiana", "direction", "harry", "basketball", "objects", "ends", "delete", "assembly", "nuclear", "mouse",
	"signal", "criminal", "issued", "brain", "sexual", "wisconsin", "powerful", "obtained", "da", "cast", "flower", "personnel",
	"passed", "supplied", "identified", "falls", "pic", "soul", "aids", "opinions", "promote", "stated", "stats", "hawaii",
	"professionals", "appears", "carry", "flag", "decided", "covers", "em", "advantage", "designs", "maintain", "tourism", "priority",
	"newsletters", "adults", "clips", "savings", "iv", "graphic", "atom", "payments", "estimated", "binding", "brief", "ended",
	"winning", "eight", "anonymous", "straight", "script", "served", "wants", "miscellaneous", "prepared", "void", "dining", "alert",
	"integration", "atlanta", "dakota", "tag", "interview", "mix", "framework", "disk", "installed", "credits", "clearly", "fix",
	"handle", "sweet", "desk", "criteria", "pubmed", "dave", "massachusetts", "diego", "hong", "vice", "associate", "ne",
	"truck", "behavior", "enlarge", "ray", "frequently", "revenue", "measure", "changing", "votes", "du", "duty", "discussions",
	"gain", "festival", "laboratory", "ocean", "flights", "experts", "signs", "lack", "depth", "iowa", "whatever", "logged",
	"laptop", "vintage", "exactly", "dry", "explore", "maryland", "spa", "concept", "nearly", "eligible", "checkout", "reality",
	"forgot", "handling", "origin", "gaming", "feeds", "billion", "destination", "scotland", "faster", "intelligence", "dallas", "con",
	"ups", "nations", "route", "followed", "specifications", "broken", "tripadvisor", "frank", "alaska", "zoom", "residential", "anime",
	"speak", "decisions", "industries", "protocol", "query", "clip", "partnership", "editorial", "expression", "es", "equity", "provisions",
	"speech", "wire", "principles", "suggestions", "rural", "shared", "sounds", "replacement", "tape", "strategic", "judge", "spam",
	"economics", "acid", "bytes", "cent", "forced", "compatible", "apartment", "height", "null", "zero", "speaker", "filed",
	"netherlands", "obtain", "consulting", "recreation", "offices", "designer", "remain", "managed", "failed", "marriage", "roll", "korea",
	"banks", "participants", "bath", "aa", "kelly", "leads", "negative", "austin", "favorites", "toronto", "theater", "springs",
	"missouri", "andrew", "var", "perform", "translation", "estimates", "font", "assets", "injury", "joseph", "ministry", "drivers",
	"lawyer", "figures", "married", "protected", "proposal", "sharing", "philadelphia", "waiting", "birthday", "beta", "fail", "gratis",
	"banking", "officials", "brian", "toward", "slightly", "assist", "conduct", "contained", "lingerie", "legislation", "calling", "parameters",
	"jazz", "serving", "bags", "profiles", "miami", "comics", "matters", "houses", "doc", "postal", "relationships", "tennessee",
	"wear", "controls", "breaking", "combined", "ultimate", "wales", "representative", "frequency", "introduced", "minor", "finish", "departments",
	"residents", "noted", "displayed", "mom", "reduced", "physics", "rare", "spent", "performed", "extreme", "samples", "davis",
	"daniel", "bars", "reviewed", "row", "oz", "forecast", "removed", "helps", "singles", "administrator", "cycle", "amounts",
	"contain", "accuracy", "dual", "rise", "usd", "sleep", "pharmacy", "brazil", "creation", "static", "scene", "hunter",
	"addresses", "crystal", "famous", "writer", "chairman", "violence", "fans", "oklahoma", "speakers", "drink", "academy", "dynamic",
	"gender", "eat", "permanent", "agriculture", "dell", "cleaning", "constitutes", "portfolio", "practical", "delivered", "collectibles", "infrastructure",
	"exclusive", "seat", "concerns", "vendor", "originally", "intel", "utilities", "philosophy", "regulation", "officers", "reduction", "aim",
	"bids", "referred", "supports", "nutrition", "recording", "regions", "junior", "toll", "les", "cape", "ann", "rings",
	"meaning", "tip", "secondary", "wonderful", "ladies", "henry", "ticket", "announced", "agreed", "prevention", "whom", "ski",
	"soccer", "math", "import", "posting", "presence", "instant", "mentioned", "automatic", "healthcare", "viewing", "maintained", "increasing",
	"majority", "connected", "christ", "dan", "dogs", "directors", "aspects", "austria", "ahead", "participation", "scheme", "utility",
	"preview", "fly", "manner", "matrix", "containing", "combination", "devel", "amendment", "despite", "strength", "guaranteed", "turkey",
	"libraries", "proper", "distributed", "degrees", "singapore", "enterprises", "delta", "fear", "seeking", "inches", "convention", "shares",
	"principal", "standing", "comfort", "colors", "wars", "cisco", "ordering", "kept", "alpha", "appeal", "cruise", "bonus",
	"certification", "previously", "bookmark", "buildings", "specials", "beat", "disney", "household", "batteries", "adobe", "smoking", "becomes",
	"drives", "arms", "alabama", "tea", "improved", "trees", "avg", "achieve", "positions", "dress", "subscription", "dealer",
	"contemporary", "utah", "nearby", "rom", "carried", "happen", "exposure", "panasonic", "hide", "permalink", "signature", "gambling",
	"refer", "miller", "provision", "outdoors", "clothes", "caused", "luxury", "babes", "frames", "certainly", "indeed", "newspaper",
	"toy", "circuit", "layer", "printed", "removal", "easier", "liability", "trademark", "hip", "printers", "faqs", "nine",
	"adding", "kentucky", "mostly", "eric", "spot", "taylor", "trackback", "prints", "spend", "factory", "interior", "revised",
	"americans", "optical", "promotion", "relative", "clock", "dot", "hiv", "identity", "suites", "conversion", "feeling", "hidden",
	"reasonable", "victoria", "serial", "relief", "revision", "broadband", "influence", "ratio", "pda", "importance", "onto", "planet",
	"webmaster", "copies", "recipe", "zum", "permit", "seeing", "proof", "dna", "diff", "tennis", "bass", "prescription",
	"bedroom", "empty", "instance", "hole", "pets", "ride", "licensed", "orlando", "specifically", "tim", "bureau", "maine",
	"represent", "conservation", "pair", "ideal", "specs", "recorded", "don", "pieces", "finished", "parks", "dinner", "lawyers",
	"sydney", "stress", "cream", "runs", "trends", "discover", "ap", "patterns", "boxes", "louisiana", "hills", "javascript",
	"fourth", "marketplace", "evil", "aware", "wilson", "shape", "evolution", "irish", "certificates", "objectives", "stations", "suggested",
	"op", "remains", "acc", "greatest", "firms", "concerned", "euro", "operator", "structures", "generic", "encyclopedia", "usage",
	"ink", "charts", "continuing", "mixed", "census", "interracial", "peak", "competitive", "exist", "wheel", "transit", "suppliers",
	"salt", "compact", "poetry", "lights", "tracking", "bell", "keeping", "preparation", "attempt", "receiving", "matches", "accordance",
	"width", "noise", "engines", "array", "discussed", "accurate", "stephen", "elizabeth", "climate", "reservations", "pin", "playstation",
	"alcohol", "greek", "instruction", "managing", "annotation", "raw", "differences", "walking", "explain", "smaller", "newest", "establish",
	"gnu", "happened", "expressed", "jeff", "extent", "sharp", "lesbians", "ben", "lane", "paragraph", "mathematics", "aol",
	"compensation", "ce", "export", "managers", "aircraft", "modules", "sweden", "conflict", "conducted", "versions", "employer", "occur",
	"percentage", "knows", "mississippi", "describe", "concern", "backup", "requested", "citizens", "connecticut", "heritage", "personals", "immediate",
	"holding", "trouble", "spread", "coach", "kevin", "agricultural", "expand", "supporting", "audience", "assigned", "jordan", "collections",
	"ages", "participate", "plug", "specialist", "cook", "affect", "virgin", "experienced", "investigation", "raised", "hat", "institution",
	"directed", "dealers", "searching", "sporting", "helping", "perl", "affected", "lib", "bike", "totally", "plate", "expenses",
	"indicate", "blonde", "ab", "proceedings", "transmission", "anderson", "utc", "characteristics", "der", "organic", "seek", "experiences",
	"albums", "cheats", "extremely", "verzeichnis", "contracts", "guests", "hosted", "diseases", "concerning", "developers", "equivalent", "chemistry",
	"tony", "neighborhood", "nevada", "kits", "thailand", "variables", "agenda", "anyway", "continues", "tracks", "advisory", "cam",
	"curriculum", "logic", "template", "circle", "soil", "grants", "anywhere", "psychology", "responses", "atlantic", "wet", "circumstances",
	"edward", "investor", "identification", "ram", "leaving", "wildlife", "appliances", "matt", "elementary", "cooking", "speaking", "sponsors",
	"fox", "unlimited", "respond", "sizes", "plain", "exit", "entered", "iran", "arm", "keys", "launch", "wave",
	"checking", "costa", "belgium", "printable", "holy", "acts", "guidance", "mesh", "trail", "enforcement", "symbol", "crafts",
	"highway", "buddy", "hardcover", "observed", "dean", "setup", "poll", "booking", "glossary", "fiscal", "celebrity", "styles",
	"denver", "unix", "filled", "bond", "channels", "ericsson", "appendix", "notify", "blues", "chocolate", "pub", "portion",
	"scope", "hampshire", "supplier", "cables", "cotton", "bluetooth", "controlled", "requirement", "authorities", "biology", "dental", "border",
	"ancient", "debate", "representatives", "starts", "pregnancy", "causes", "arkansas", "biography", "leisure", "attractions", "learned", "transactions",
	"notebook", "explorer", "historic", "attached", "opened", "disabled", "authorized", "upcoming", "britain", "concert", "retirement", "scores",
	"financing", "efficiency", "comedy", "adopted", "efficient", "weblog", "linear", "commitment", "specialty", "bears", "jean", "hop",
	"carrier", "edited", "constant", "visa", "mouth", "jewish", "meter", "linked", "portland", "interviews", "concepts", "gun",
	"reflect", "pure", "deliver", "wonder", "lessons", "fruit", "begins", "qualified", "reform", "lens", "alerts", "treated",
	"discovery", "draw", "mysql", "classified", "relating", "assume", "confidence", "confirm", "warm", "neither", "lewis", "howard",
	"offline", "leaves", "engineer", "lifestyle", "consistent", "replace", "clearance", "connections", "inventory", "converter", "organisation", "babe",
	"checks", "reached", "becoming", "safari", "objective", "indicated", "sugar", "crew", "legs", "sam", "stick", "securities",
	"allen", "relation", "enabled", "genre", "slide", "montana", "volunteer", "tested", "rear", "democratic", "enhance", "switzerland",
	"exact", "bound", "parameter", "adapter", "processor", "node", "formal", "dimensions", "contribute", "lock", "hockey", "micro",
	"colleges", "laptops", "mile", "showed", "challenges", "editors", "mens", "threads", "bowl", "supreme", "brothers", "recognition",
	"presents", "ref", "tank", "submission", "dolls", "estimate", "encourage", "navy", "regulatory", "inspection", "consumers", "cancel",
	"limits", "territory", "transaction", "manchester", "weapons", "paint", "delay", "pilot", "outlet", "contributions", "continuous", "czech",
	"resulting", "cambridge", "initiative", "novel", "pan", "execution", "disability", "increases", "ultra", "winner", "idaho", "contractor",
	"episode", "examination", "potter", "dish", "plays", "bulletin", "ia", "indicates", "modify", "oxford", "adam", "truly",
	"epinions", "painting", "committed", "extensive", "affordable", "universe", "candidate", "databases", "patent", "slot", "outstanding", "ha",
	"eating", "perspective", "planned", "watching", "lodge", "messenger", "mirror", "tournament", "consideration", "discounts", "sterling", "sessions",
	"kernel", "stocks", "buyers", "journals", "gray", "catalogue", "ea", "jennifer", "antonio", "charged", "broad", "taiwan",
	"und", "chosen", "demo", "greece", "swiss", "sarah", "clark", "terminal", "publishers", "nights", "behalf", "caribbean",
	"liquid", "rice", "nebraska", "loop", "salary", "reservation", "foods", "gourmet", "guard", "properly", "orleans", "saving",
	"remaining", "resume", "twenty", "newly", "raise", "prepare", "avatar", "gary", "depending", "illegal", "expansion", "vary",
	"hundreds", "rome", "arab", "lincoln", "premier", "purchased", "milk", "decide", "consent", "drama", "visiting", "performing",
	"downtown", "keyboard", "contest", "collected", "bands", "boot", "suitable", "absolutely", "millions", "lunch", "audit", "push",
	"chamber", "guinea", "findings", "muscle", "featuring", "iso", "implement", "clicking", "scheduled", "polls", "typical", "sum",
	"misc", "calculator", "significantly", "temporary", "attend", "shower", "alan", "sending", "jason", "dear", "sufficient", "holdem",
	"shell", "province", "catholic", "oak", "vat", "awareness", "vancouver", "governor", "beer", "seemed", "contribution", "measurement",
	"swimming", "spyware", "formula", "constitution", "packaging", "solar", "jose", "catch", "jane", "pakistan", "reliable", "consultation",
	"northwest", "sir", "doubt", "earn", "finder", "unable", "periods", "classroom", "tasks", "democracy", "attacks", "kim",
	"wallpaper", "merchandise", "const", "resistance", "doors", "symptoms", "resorts", "biggest", "memorial", "visitor", "twin", "forth",
	"insert", "baltimore", "gateway", "ky", "dont", "alumni", "drawing", "candidates", "charlotte", "ordered", "biological", "fighting",
	"transition", "happens", "preferences", "romance", "instrument", "bruce", "split", "themes", "powers", "heaven", "bits", "pregnant",
	"twice", "classification", "focused", "egypt", "physician", "hollywood", "bargain", "wikipedia", "cellular", "norway", "vermont", "asking",
	"blocks", "normally", "lo", "spiritual", "hunting", "diabetes", "suit", "shift", "chip", "res", "bodies", "photographs",
	"cutting", "wow", "simon", "writers", "marks", "flexible", "mapping", "numerous", "relatively", "birds", "satisfaction", "represents",
	"char", "indexed", "pittsburgh", "superior", "preferred", "saved", "paying", "cartoon", "shots", "intellectual", "moore", "granted",
	"choices", "carbon", "spending", "comfortable", "magnetic", "interaction", "listening", "effectively", "registry", "crisis", "outlook", "massive",
	"denmark", "employed", "bright", "treat", "header", "poverty", "formed", "piano", "echo", "que", "grid", "sheets",
	"patrick", "experimental", "puerto", "revolution", "consolidation", "displays", "plasma", "allowing", "earnings", "voip", "mystery", "landscape",
	"dependent", "mechanical", "journey", "delaware", "bidding", "consultants", "risks", "applicant", "charter", "fig", "barbara", "cooperation",
	"counties", "acquisition", "ports", "implemented", "directories", "recognized", "dreams", "blogger", "notification", "licensing", "stands", "occurred",
	"textbooks", "rapid", "pull", "hairy", "diversity", "cleveland", "ut", "reverse", "deposit", "seminar", "investments", "latina",
	"nasa", "wheels", "specify", "accessibility", "dutch", "sensitive", "templates", "formats", "tab", "depends", "boots", "holds",
	"router", "concrete", "si", "editing", "poland", "folder", "womens", "completion", "upload", "pulse", "universities", "technique",
	"contractors", "voting", "courts", "notices", "subscriptions", "calculate", "detroit", "alexander", "broadcast", "converted", "metro", "toshiba",
	"anniversary", "improvements", "strip", "specification", "pearl", "accident", "nick", "accessible", "accessory", "resident", "plot", "qty",
	"possibly", "airline", "typically", "representation", "regard", "pump", "exists", "arrangements", "smooth", "conferences", "strike", "consumption",
	"birmingham", "flashing", "narrow", "afternoon", "threat", "surveys", "sitting", "putting", "consultant", "controller", "ownership", "committees",
	"legislative", "researchers", "vietnam", "trailer", "anne", "gardens", "missed", "malaysia", "unsubscribe", "antique", "labels", "willing",
	"bio", "molecular", "acting", "heads", "stored", "exam", "logos", "residence", "attorneys", "antiques", "density", "hundred",
	"ryan", "operators", "strange", "sustainable", "philippines", "statistical", "beds", "mention", "innovation", "employers", "grey", "parallel",
	"honda", "amended", "operate", "bills", "bold", "stable", "opera", "definitions", "von", "doctors", "lesson", "cinema",
	"asset", "ag", "scan", "elections", "drinking", "reaction", "blank", "enhanced", "entitled", "severe", "generate", "stainless",
	"newspapers", "hospitals", "vi", "deluxe", "humor", "aged", "monitors", "exception", "lived", "duration", "bulk", "successfully",
	"indonesia", "pursuant", "sci", "fabric", "edt", "visits", "primarily", "tight", "domains", "capabilities", "pmid", "contrast",
	"recommendation", "flying", "recruitment", "sin", "berlin", "cute", "organized", "ba", "para", "siemens", "adoption", "improving",
	"expensive", "meant", "capture", "pounds", "buffalo", "organisations", "plane", "explained", "seed", "programmes", "desire", "expertise",
	"mechanism", "camping", "ee", "jewellery", "meets", "welfare", "peer", "caught", "eventually", "marked", "driven", "measured",
	"bottle", "agreements", "considering", "innovative", "marshall", "massage", "rubber", "conclusion", "closing", "tampa", "thousand", "meat",
	"legend", "grace", "susan", "ing", "adams", "python", "monster", "alex", "bang", "villa", "bone", "columns",
	"disorders", "bugs", "collaboration", "hamilton", "detection", "cookies", "inner", "formation", "tutorial", "med", "engineers", "entity",
	"cruises", "holder", "proposals", "moderator", "tutorials", "settlement", "portugal", "lawrence", "roman", "duties", "valuable", "tone",
	"collectables", "ethics", "forever", "captain", "fantastic", "imagine", "brings", "heating", "leg", "neck", "wing", "governments",
	"purchasing", "scripts", "abc", "stereo", "appointed", "taste", "dealing", "commit", "tiny", "operational", "rail", "airlines",
	"liberal", "jay", "trips", "gap", "sides", "tube", "turns", "corresponding", "descriptions", "cache", "belt", "jacket",
	"determination", "animation", "oracle", "er", "matthew", "lease", "productions", "aviation", "hobbies", "excess", "console", "commands",
	"telecommunications", "instructor", "achieved", "injuries", "shipped", "seats", "approaches", "biz", "alarm", "voltage", "anthony", "nintendo",
	"usual", "loading", "stamps", "appeared", "franklin", "angle", "rob", "vinyl", "highlights", "mining", "designers", "melbourne",
	"ongoing", "worst", "imaging", "betting", "scientists", "liberty", "wyoming", "blackjack", "argentina", "era", "convert", "possibility",
	"analyst", "commissioner", "dangerous", "garage", "exciting", "reliability", "thongs", "unfortunately", "respectively", "volunteers", "attachment", "ringtone",
	"finland", "morgan", "derived", "pleasure", "honor", "asp", "oriented", "eagle", "desktops", "pants", "columbus", "nurse",
	"prayer", "appointment", "workshops", "hurricane", "quiet", "luck", "postage", "producer", "represented", "mortgages", "dial", "responsibilities",
	"cheese", "comic", "carefully", "jet", "productivity", "investors", "par", "underground", "diagnosis", "maker", "crack", "principle",
	"picks", "vacations", "gang", "semester", "calculated", "fetish", "applies", "casinos", "appearance", "smoke", "apache", "filters",
	"incorporated", "craft", "cake", "notebooks", "apart", "fellow", "blind", "lounge", "mad", "algorithm", "semi", "coins",
	"andy", "gross", "strongly", "cafe", "valentine", "hilton", "ken", "proteins", "horror", "su", "exp", "familiar",
	"capable", "douglas", "debian", "till", "involving", "pen", "investing", "christopher", "admission", "epson", "shoe", "elected",
	"carrying", "victory", "sand", "madison", "terrorism", "joy", "editions", "cpu", "mainly", "ethnic", "parliament", "actor",
	"finds", "seal", "situations", "fifth", "allocated", "citizen", "vertical", "corrections", "structural", "municipal", "describes", "prize",
	"occurs", "jon", "absolute", "disabilities", "consists", "anytime", "substance", "prohibited", "addressed", "lies", "pipe", "soldiers",
	"guardian", "lecture", "simulation", "layout", "initiatives", "ill", "concentration", "classics", "lay", "interpretation", "horses", "dirty",
	"deck", "wayne", "donate", "taught", "bankruptcy", "optimization", "substances", "prove", "discovered", "wings", "breaks", "genetic",
	"restrictions", "participating", "waters", "thin", "exhibition", "prefer", "ridge", "cabinet", "modem", "harris", "bringing", "dose",
	"evaluate", "tiffany", "tropical", "collect", "composition", "toyota", "streets", "nationwide", "vector", "definitely", "shaved", "turning",
	"buffer", "purple", "existence", "commentary", "larry", "limousines", "developments", "def", "immigration", "destinations", "lets", "mutual",
	"pipeline", "necessarily", "syntax", "li", "attribute", "skill", "chairs", "everyday", "apparently", "surrounding", "mountains", "moves",
	"popularity", "inquiry", "ethernet", "checked", "exhibit", "throw", "trend", "sierra", "visible", "cats", "desert", "postposted",
	"ya", "oldest", "rhode", "nba", "coordinator", "obviously", "mercury", "steven", "handbook", "greg", "navigate", "worse",
	"summit", "victims", "epa", "spaces", "fundamental", "burning", "escape", "coupons", "somewhat", "receiver", "substantial", "progressive",
	"boats", "glance", "scottish", "championship", "arcade", "richmond", "sacramento", "impossible", "ron", "russell", "tells", "obvious",
	"fiber", "depression", "graph", "covering", "platinum", "judgment", "bedrooms", "talks", "filing", "foster", "modeling", "passing",
	"awarded", "testimonials", "trials", "tissue", "memorabilia", "clinton", "masters", "bonds", "cartridge", "alberta", "explanation", "folk",
	"org", "commons", "cincinnati", "subsection", "fraud", "electricity", "permitted", "spectrum", "arrival", "pottery", "emphasis", "roger",
	"aspect", "workplace", "mexican", "confirmed", "counts", "priced", "wallpapers", "hist", "crash", "lift", "desired", "inter",
	"closer", "assumes", "heights", "shadow", "riding", "infection", "firefox", "lisa", "expense", "grove", "eligibility", "venture",
	"clinic", "korean", "healing", "mall", "entering", "packet", "spray", "studios", "involvement", "dad", "buttons", "placement",
	"observations", "funded", "thompson", "winners", "extend", "roads", "subsequent", "pat", "dublin", "rolling", "fell", "motorcycle",
	"yard", "disclosure", "establishment", "memories", "nelson", "te", "arrived", "creates", "faces", "tourist", "av", "murder",
	"sean", "adequate", "senator", "yield", "presentations", "grades", "cartoons", "pour", "digest", "reg", "lodging", "tion",
	"dust", "hence", "wiki", "entirely", "replaced", "radar", "rescue", "undergraduate", "losses", "combat", "reducing", "stopped",
	"occupation", "lakes", "donations", "associations", "citysearch", "closely", "radiation", "diary", "seriously", "kings", "shooting", "kent",
	"adds", "ear", "flags", "pci", "baker", "launched", "elsewhere", "pollution", "conservative", "guestbook", "shock", "effectiveness",
	"walls", "abroad", "ebony", "tie", "ward", "drawn", "arthur", "ian", "visited", "roof", "walker", "demonstrate",
	"atmosphere", "suggests", "kiss", "beast", "ra", "operated", "experiment", "targets", "overseas", "purchases", "dodge", "counsel",
	"federation", "pizza", "invited", "yards", "assignment", "chemicals", "gordon", "mod", "farmers", "queries", "rush", "ukraine",
	"absence", "nearest", "cluster", "vendors", "mpeg", "whereas", "yoga", "serves", "woods", "surprise", "lamp", "rico",
	"partial", "shoppers", "phil", "everybody", "couples", "nashville", "ranking", "jokes", "ceo", "simpson", "sublime", "counseling",
	"palace", "acceptable", "satisfied", "glad", "wins", "measurements", "verify", "globe", "trusted", "copper", "milwaukee", "rack",
	"medication", "warehouse", "shareware", "ec", "rep", "dicke", "kerry", "receipt", "supposed", "ordinary", "nobody", "ghost",
	"violation", "configure", "stability", "mit", "applying", "southwest", "boss", "pride", "institutional", "expectations", "independence", "knowing",
	"reporter", "metabolism", "keith", "champion", "cloudy", "linda", "ross", "personally", "chile", "anna", "plenty", "solo",
	"sentence", "throat", "ignore", "maria", "uniform", "excellence", "wealth", "tall", "somewhere", "vacuum", "dancing", "attributes",
	"recognize", "brass", "writes", "plaza", "pdas", "outcomes", "survival", "quest", "publish", "sri", "screening", "toe",
	"thumbnail", "trans", "jonathan", "whenever", "nova", "lifetime", "api", "pioneer", "booty", "forgotten", "acrobat", "plates",
	"acres", "venue", "athletic", "thermal", "essays", "vital", "telling", "fairly", "coastal", "config", "charity", "intelligent",
	"edinburgh", "excel", "modes", "obligation", "campbell", "wake", "harbor", "hungary", "traveler", "urw", "segment", "realize",
	"regardless", "lan", "puzzle", "rising", "aluminum", "wells", "wishlist", "opens", "insight", "restricted", "republican", "secrets",
	"lucky", "latter", "merchants", "thick", "trailers", "repeat", "syndrome", "philips", "attendance", "penalty", "drum", "glasses",
	"enables", "nec", "iraqi", "builder", "vista", "jessica", "chips", "terry", "foto", "ease", "arguments", "amsterdam",
	"arena", "adventures", "pupils", "stewart", "announcement", "tabs", "outcome", "appreciate", "expanded", "casual", "grown", "polish",
	"lovely", "extras", "centres", "jerry", "clause", "lands", "ri", "troops", "indoor", "bulgaria", "armed", "broker",
	"charger", "regularly", "believed", "pine", "cooling", "tend", "gulf", "rick", "trucks", "mechanisms", "laura", "shopper",
	"tokyo", "partly", "nikon", "customize", "tradition", "candy", "pills", "tiger", "donald", "folks", "sensor", "exposed",
	"telecom", "hunt", "angels", "deputy", "indicators", "sealed", "thai", "emissions", "physicians", "loaded", "fred", "complaint",
	"scenes", "experiments", "afghanistan", "boost", "spanking", "scholarship", "governance", "mill", "founded", "supplements", "chronic", "icons",
	"moral", "den", "catering", "aud", "finger", "keeps", "pound", "locate", "camcorder", "trained", "burn", "implementing",
	"roses", "labs", "ourselves", "bread", "tobacco", "wooden", "motors", "roberts", "incident", "dynamics", "conversation", "decrease",
	"chest", "pension", "billy", "revenues", "emerging", "worship", "capability", "ak", "fe", "craig", "herself", "producing",
	"churches", "precision", "damages", "reserves", "contributed", "solve", "shorts", "reproduction", "minority", "diverse", "amp", "ingredients",
	"ah", "johnny", "sole", "franchise", "recorder", "complaints", "facing", "nancy", "promotions", "tones", "passion", "rehabilitation",
	"maintaining", "sight", "laid", "clay", "defence", "patches", "refund", "usc", "towns", "environments", "trembl", "divided",
	"reception", "amd", "wise", "emails", "cyprus", "odds", "correctly", "insider", "seminars", "consequences", "makers", "hearts",
	"geography", "appearing", "integrity", "worry", "discrimination", "eve", "carter", "legacy", "marc", "pleased", "danger", "vitamin",
	"widely", "processed", "phrase", "genuine", "raising", "implications", "functionality", "paradise", "hybrid", "reads", "roles", "intermediate",
	"emotional", "sons", "leaf", "pad", "glory", "platforms", "ja", "bigger", "billing", "diesel", "versus", "combine",
	"overnight", "geographic", "exceed", "rod", "saudi", "fault", "cuba", "preliminary", "districts", "introduce", "silk", "promotional",
	"kate", "chevrolet", "babies", "bi", "karen", "compiled", "romantic", "revealed", "specialists", "generator", "albert", "examine",
	"jimmy", "graham", "suspension", "bristol", "margaret", "compaq", "correction", "slowly", "authentication", "communicate", "rugby", "supplement",
	"showtimes", "cal", "portions", "infant", "promoting", "sectors", "samuel", "fluid", "grounds", "fits", "kick", "regards",
	"meal", "ta", "hurt", "machinery", "bandwidth", "unlike", "equation", "baskets", "probability", "pot", "dimension", "wright",
	"img", "barry", "proven", "schedules", "admissions", "cached", "warren", "slip", "studied", "reviewer", "involves", "quarterly",
	"profits", "devil", "grass", "comply", "marie", "florist", "illustrated", "cherry", "continental", "alternate", "deutsch", "achievement",
	"limitations", "kenya", "webcam", "cuts", "funeral", "nutten", "earrings", "enjoyed", "automated", "chapters", "charlie", "quebec",
	"passenger", "convenient", "dennis", "mars", "francis", "sized", "manga", "noticed", "socket", "silent", "literary", "egg",
	"signals", "caps", "orientation", "pill", "theft", "childhood", "swing", "symbols", "lat", "meta", "analog", "facial",
	"choosing", "talent", "dated", "flexibility", "seeker", "wisdom", "shoot", "boundary", "mint", "packard", "offset", "payday",
	"philip", "elite", "gi", "spin", "holders", "believes", "swedish", "poems", "deadline", "jurisdiction", "robot", "displaying",
	"witness", "collins", "equipped", "stages", "encouraged", "sur", "winds", "powder", "broadway", "acquired", "assess", "wash",
	"cartridges", "stones", "entrance", "roots", "declaration", "losing", "attempts", "gadgets", "noble", "glasgow", "automation", "impacts",
	"rev", "gospel", "advantages", "shore", "loves", "induced", "preparing", "loose", "aims", "recipient", "linking", "extensions",
	"appeals", "earned", "illness", "islamic", "athletics", "southeast", "ieee", "ho", "alternatives", "pending", "parker", "determining",
	"lebanon", "corp", "personalized", "kennedy", "conditioning", "teenage", "soap", "ae", "triple", "cooper", "nyc", "vincent",
	"jam", "secured", "unusual", "answered", "partnerships", "destruction", "slots", "increasingly", "migration", "disorder", "routine", "toolbar",
	"basically", "rocks", "conventional", "titans", "applicants", "wearing", "axis", "sought", "genes", "mounted", "habitat", "firewall",
	"median", "guns", "scanner", "herein", "occupational", "animated", "judicial", "rio", "adjustment", "hero", "integer", "treatments",
	"bachelor", "attitude", "camcorders", "engaged", "falling", "basics", "montreal", "carpet", "struct", "lenses", "binary", "genetics",
	"attended", "difficulty", "punk", "collective", "coalition", "pi", "dropped", "enrollment", "duke", "walter", "ai", "pace",
	"besides", "wage", "producers", "ot", "collector", "arc", "hosts", "interfaces", "advertisers", "moments", "atlas", "strings",
	"dawn", "representing", "observation", "feels", "torture", "carl", "deleted", "coat", "mitchell", "rica", "restoration", "convenience",
	"returning", "ralph", "opposition", "container", "yr", "defendant", "warner", "confirmation", "app", "embedded", "inkjet", "supervisor",
	"corps", "actors", "liver", "peripherals", "liable", "brochure", "morris", "bestsellers", "petition", "eminem", "recall", "antenna",
	"picked", "assumed", "departure", "minneapolis", "belief", "killing", "bikini", "memphis", "shoulder", "decor", "lookup", "texts",
	"harvard", "brokers", "roy", "ion", "diameter", "ottawa", "doll", "ic", "podcast", "seasons", "peru", "interactions",
	"refine", "bidder", "singer", "evans", "literacy", "fails", "aging", "nike", "intervention", "fed", "plugin", "attraction",
	"diving", "invite", "modification", "alice", "latinas", "suppose", "customized", "reed", "involve", "moderate", "terror", "younger",
	"thirty", "mice", "opposite", "understood", "rapidly", "dealtime", "ban", "temp", "intro", "mercedes", "zus", "assurance",
	"clerk", "happening", "vast", "mills", "outline", "amendments", "tramadol", "holland", "receives", "jeans", "metropolitan", "compilation",
	"verification", "fonts", "ent", "odd", "wrap", "refers", "mood", "favor", "veterans", "quiz", "sigma", "attractive",
	"occasion", "recordings", "jefferson", "victim", "demands", "sleeping", "careful", "ext", "beam", "gardening", "obligations", "arrive",
	"orchestra", "sunset", "tracked", "moreover", "minimal", "polyphonic", "lottery", "tops", "framed", "aside", "outsourcing", "licence",
	"adjustable", "allocation", "michelle", "essay", "discipline", "amy", "demonstrated", "dialogue", "identifying", "alphabetical", "camps", "declared",
	"dispatched", "aaron", "handheld", "trace", "disposal", "shut", "florists", "packs", "ge", "installing", "switches", "romania",
	"voluntary", "ncaa", "thou", "consult", "greatly", "blogging", "mask", "cycling", "midnight", "commonly", "pe", "photographer",
	"inform", "turkish", "coal", "messaging", "pentium", "quantum", "murray", "intent", "zoo", "largely", "pleasant", "announce",
	"constructed", "additions", "requiring", "spoke", "aka", "arrow", "engagement", "sampling", "rough", "weird", "tee", "refinance",
	"lion", "inspired", "holes", "weddings", "blade", "suddenly", "oxygen", "cookie", "meals", "canyon", "goto", "meters",
	"merely", "calendars", "arrangement", "conclusions", "passes", "bibliography", "pointer", "compatibility", "stretch", "durham", "furthermore", "permits",
	"cooperative", "muslim", "neil", "sleeve", "netscape", "cleaner", "cricket", "beef", "feeding", "stroke", "township", "rankings",
	"measuring", "cad", "hats", "robin", "robinson", "jacksonville", "strap", "headquarters", "sharon", "crowd", "transfers", "surf",
	"olympic", "transformation", "remained", "attachments", "dir", "entities", "customs", "administrators", "personality", "rainbow", "hook", "roulette",
	"decline", "gloves", "israeli", "medicare", "cord", "skiing", "facilitate", "subscriber", "valve", "val", "hewlett", "explains",
	"proceed", "flickr", "feelings", "knife", "jamaica", "priorities", "shelf", "bookstore", "timing", "parenting", "adopt", "denied",
	"fotos", "incredible", "britney", "freeware", "donation", "outer", "crop", "deaths", "rivers", "commonwealth", "pharmaceutical", "manhattan",
	"tales", "katrina", "workforce", "islam", "nodes", "tu", "fy", "thumbs", "cited", "lite", "hub", "targeted",
	"organizational", "skype", "realized", "twelve", "founder", "decade", "gamecube", "dispute", "portuguese", "titten", "adverse", "everywhere",
	"excerpt", "eng", "steam", "discharge", "ef", "drinks", "ace", "voices", "acute", "halloween", "climbing", "stood",
	"sing", "tons", "perfume", "carol", "honest", "albany", "hazardous", "restore", "stack", "methodology", "somebody", "sue",
	"ep", "housewares", "reputation", "resistant", "democrats", "recycling", "hang", "curve", "creator", "amber", "qualifications", "museums",
	"coding", "slideshow", "tracker", "variation", "passage", "transferred", "trunk", "hiking", "pierre", "jelsoft", "headset", "photograph",
	"oakland", "colombia", "waves", "camel", "distributor", "lamps", "underlying", "hood", "wrestling", "suicide", "archived", "photoshop",
	"chi", "arabia", "gathering", "projection", "juice", "chase", "mathematical", "logical", "sauce", "fame", "extract", "specialized",
	"diagnostic", "panama", "indianapolis", "payable", "corporations", "courtesy", "criticism", "automobile", "confidential", "statutory", "accommodations", "athens",
	"northeast", "downloaded", "judges", "seo", "retired", "isp", "remarks", "detected", "decades", "paintings", "walked", "arising",
	"nissan", "bracelet", "ins", "eggs", "juvenile", "injection", "yorkshire", "populations", "protective", "afraid", "acoustic", "railway",
	"cassette", "initially", "indicator", "pointed", "causing", "mistake", "norton", "locked", "eliminate", "fusion", "mineral", "sunglasses",
	"ruby", "steering", "beads", "fortune", "preference", "canvas", "threshold", "parish", "claimed", "screens", "cemetery", "planner",
	"croatia", "flows", "stadium", "venezuela", "exploration", "mins", "fewer", "sequences", "coupon", "nurses", "stem", "proxy",
	"astronomy", "lanka", "opt", "edwards", "drew", "contests", "flu", "translate", "announces", "costume", "tagged", "berkeley",
	"voted", "killer", "bikes", "gates", "adjusted", "rap", "tune", "bishop", "pulled", "corn", "shaped", "compression",
	"seasonal", "establishing", "farmer", "counters", "puts", "constitutional", "grew", "perfectly", "tin", "slave", "instantly", "cultures",
	"norfolk", "coaching", "examined", "trek", "encoding", "litigation", "submissions", "oem", "heroes", "painted", "lycos", "ir",
	"zdnet", "broadcasting", "horizontal", "artwork", "cosmetic", "resulted", "portrait", "terrorist", "informational", "ethical", "carriers", "ecommerce",
	"mobility", "floral", "builders", "ties", "struggle", "schemes", "suffering", "neutral", "fisher", "rat", "spears", "prospective",
	"bedding", "ultimately", "joining", "heading", "equally", "artificial", "bearing", "spectacular", "coordination", "connector", "brad", "combo",
	"seniors", "worlds", "guilty", "affiliated", "activation", "naturally", "haven", "tablet", "jury", "dos", "tail", "subscribers",
	"charm", "lawn", "violent", "mitsubishi", "underwear", "basin", "soup", "potentially", "ranch", "constraints", "crossing", "inclusive",
	"dimensional", "cottage", "drunk", "considerable", "crimes", "resolved", "mozilla", "byte", "toner", "nose", "latex", "branches",
	"anymore", "oclc", "delhi", "holdings", "alien", "locator", "selecting", "processors", "pantyhose", "broke", "nepal", "zimbabwe",
	"difficulties", "juan", "complexity", "constantly", "browsing", "resolve", "barcelona", "presidential", "documentary", "cod", "territories", "melissa",
	"moscow", "thesis", "thru", "jews", "nylon", "palestinian", "discs", "rocky", "bargains", "frequent", "trim", "nigeria",
	"ceiling", "pixels", "ensuring", "hispanic", "legislature", "hospitality", "gen", "anybody", "procurement", "diamonds", "espn", "fleet",
	"untitled", "bunch", "totals", "marriott", "singing", "theoretical", "afford", "exercises", "starring", "referral", "surveillance", "optimal",
	"quit", "distinct", "protocols", "lung", "highlight", "substitute", "inclusion", "hopefully", "brilliant", "turner", "sucking", "cents",
	"reuters", "ti", "gel", "todd", "spoken", "omega", "evaluated", "stayed", "civic", "assignments", "manuals", "doug",
	"sees", "termination", "watched", "saver", "thereof", "grill", "households", "redeem", "rogers", "grain", "aaa", "authentic",
	"regime", "wishes", "bull", "montgomery", "architectural", "louisville", "depend", "differ", "macintosh", "movements", "ranging", "monica",
	"repairs", "breath", "amenities", "virtually", "cole", "mart", "candle", "hanging", "colored", "authorization", "tale", "verified",
	"lynn", "formerly", "projector", "situated", "comparative", "seeks", "herbal", "loving", "strictly", "routing", "docs", "stanley",
	"psychological", "surprised", "retailer", "vitamins", "elegant", "gains", "renewal", "vid", "genealogy", "opposed", "deemed", "scoring",
	"expenditure", "brooklyn", "liverpool", "sisters", "critics", "connectivity", "spots", "oo", "algorithms", "hacker", "madrid", "similarly",
	"margin", "coin", "solely", "salon", "collaborative", "norman", "fda", "excluding", "turbo", "headed", "voters", "cure",
	"madonna", "arch", "ni", "murphy", "thinks", "thats", "suggestion", "phillips", "asin", "aimed", "justin", "bomb",
	"harm", "interval", "mirrors", "spotlight", "tricks", "reset", "brush", "investigate", "thy", "expansys", "panels", "repeated",
	"assault", "connecting", "spare", "logistics", "kodak", "tongue", "bowling", "tri", "danish", "pal", "monkey", "proportion",
	"filename", "skirt", "florence", "invest", "honey", "um", "analyzes", "drawings", "significance", "scenario", "lovers", "atomic",
	"approx", "symposium", "arabic", "gauge", "essentials", "junction", "protecting", "faced", "mat", "rachel", "solving", "transmitted",
	"weekends", "screenshots", "produces", "oven", "ted", "intensive", "chains", "kingston", "sixth", "engage", "deviant", "noon",
	"switching", "quoted", "adapters", "correspondence", "farms", "imports", "supervision", "cheat", "bronze", "expenditures", "sandy", "separation",
	"testimony", "suspect", "celebrities", "macro", "sender", "mandatory", "boundaries", "crucial", "syndication", "gym", "celebration", "kde",
	"adjacent", "filtering", "tuition", "spouse", "exotic", "viewer", "signup", "threats", "luxembourg", "puzzles", "reaching", "damaged",
	"cams", "receptor", "joel", "surgical", "destroy", "citation", "pitch", "autos", "yo", "premises", "perry", "proved",
	"offensive", "imperial", "dozen", "benjamin", "deployment", "teeth", "cloth", "studying", "colleagues", "stamp", "lotus", "salmon",
	"olympus", "separated", "proc", "cargo", "tan", "directive", "salem", "mate", "starter", "upgrades", "likes", "butter",
	"pepper", "weapon", "luggage", "burden", "chef", "tapes", "zones", "races", "isle", "stylish", "slim", "maple",
	"luke", "grocery", "offshore", "governing", "retailers", "depot", "kenneth", "comp", "alt", "pie", "blend", "harrison",
	"julie", "occasionally", "attending", "emission", "pete", "spec", "finest", "realty", "janet", "bow", "penn", "recruiting",
	"apparent", "instructional", "autumn", "traveling", "probe", "midi", "permissions", "biotechnology", "toilet", "ranked", "jackets", "routes",
	"packed", "excited", "outreach", "helen", "mounting", "recover", "tied", "lopez", "balanced", "prescribed", "catherine", "timely",
	"debug", "delayed", "chuck", "reproduced", "hon", "dale", "explicit", "calculation", "villas", "ebook", "consolidated", "exclude",
	"peeing", "occasions", "brooks", "equations", "newton", "oils", "sept", "exceptional", "anxiety", "bingo", "whilst", "spatial",
	"respondents", "unto", "ceramic", "prompt", "precious", "minds", "annually", "considerations", "scanners", "atm", "xanax", "eq",
	"pays", "fingers", "sunny", "ebooks", "delivers", "je", "queensland", "necklace", "musicians", "leeds", "composite", "unavailable",
	"cedar", "arranged", "lang", "theaters", "advocacy", "raleigh", "stud", "fold", "essentially", "designing", "threaded", "uv",
	"qualify", "blair", "hopes", "assessments", "mason", "diagram", "burns", "pumps", "footwear", "vic", "beijing", "peoples",
	"victor", "mario", "pos", "attach", "licenses", "utils", "removing", "advised", "brunswick", "spider", "phys", "ranges",
	"pairs", "sensitivity", "trails", "preservation", "hudson", "isolated", "calgary", "interim", "assisted", "divine", "streaming", "approve",
	"chose", "compound", "intensity", "technological", "syndicate", "abortion", "dialog", "venues", "blast", "wellness", "calcium", "newport",
	"antivirus", "addressing", "pole", "discounted", "indians", "harvest", "membrane", "prague", "previews", "bangladesh", "constitute", "locally",
	"concluded", "pickup", "desperate", "mothers", "nascar", "iceland", "demonstration", "governmental", "manufactured", "candles", "graduation", "mega",
	"bend", "sailing", "variations", "moms", "sacred", "addiction", "morocco", "chrome", "tommy", "springfield", "refused", "brake",
	"exterior", "greeting", "ecology", "oliver", "congo", "glen", "botswana", "nav", "delays", "synthesis", "olive", "undefined",
	"unemployment", "cyber", "verizon", "scored", "enhancement", "newcastle", "clone", "velocity", "lambda", "relay", "composed", "tears",
	"performances", "oasis", "baseline", "cab", "fa", "societies", "silicon", "brazilian", "identical", "petroleum", "compete", "ist",
	"norwegian", "lover", "belong", "honolulu", "beatles", "lips", "retention", "exchanges", "pond", "rolls", "thomson", "barnes",
	"soundtrack", "wondering", "malta", "daddy", "ferry", "rabbit", "profession", "seating", "dam", "separately", "physiology", "lil",
	"collecting", "das", "exports", "omaha", "tire", "participant", "scholarships", "recreational", "dominican", "chad", "electron", "loads",
	"friendship", "heather", "passport", "motel", "unions", "treasury", "warrant", "sys", "solaris", "frozen", "occupied", "josh",
	"royalty", "scales", "rally", "observer", "sunshine", "strain", "drag", "ceremony", "somehow", "arrested", "expanding", "provincial",
	"investigations", "icq", "ripe", "yamaha", "rely", "medications", "hebrew", "gained", "rochester", "dying", "laundry", "stuck",
	"solomon", "placing", "stops", "homework", "adjust", "assessed", "advertiser", "enabling", "encryption", "filling", "downloadable", "sophisticated",
	"imposed", "silence", "scsi", "focuses", "soviet", "possession", "cu", "laboratories", "vocal", "trainer", "organ", "stronger",
	"volumes", "advances", "vegetables", "lemon", "toxic", "thumbnails", "darkness", "pty", "nuts", "nail", "bizrate", "vienna",
	"implied", "span", "stanford", "sox", "stockings", "joke", "respondent", "packing", "statute", "rejected", "satisfy", "destroyed",
	"shelter", "chapel", "gamespot", "manufacture", "layers", "wordpress", "guided", "vulnerability", "accountability", "celebrate", "accredited", "appliance",
	"compressed", "bahamas", "powell", "mixture", "bench", "univ", "tub", "rider", "scheduling", "radius", "perspectives", "mortality",
	"logging", "hampton", "christians", "borders", "therapeutic", "pads", "inns", "bobby", "impressive", "accordingly", "architect", "railroad",
	"lectures", "challenging", "wines", "nursery", "harder", "cups", "ash", "microwave", "cheapest", "accidents", "travesti", "relocation",
	"stuart", "contributors", "salvador", "ali", "salad", "monroe", "tender", "violations", "foam", "temperatures", "paste", "clouds",
	"competitions", "discretion", "tanzania", "preserve", "poem", "unsigned", "staying", "cosmetics", "easter", "theories", "repository", "praise",
	"jeremy", "venice", "concentrations", "estonia", "christianity", "veteran", "streams", "landing", "signing", "executed", "katie", "negotiations",
	"realistic", "cgi", "showcase", "integral", "asks", "relax", "namibia", "generating", "christina", "congressional", "synopsis", "hardly",
	"prairie", "reunion", "composer", "bean", "absent", "photographic", "sells", "ecuador", "hoping", "accessed", "spirits", "modifications",
	"coral", "pixel", "float", "colin", "bias", "imported", "paths", "bubble", "por", "acquire", "contrary", "millennium",
	"tribune", "vessel", "acids", "focusing", "viruses", "cheaper", "admitted", "dairy", "admit", "mem", "fancy", "equality",
	"samoa", "achieving", "tap", "stickers", "fisheries", "exceptions", "reactions", "leasing", "lauren", "beliefs", "ci", "macromedia",
	"companion", "squad", "analyze", "ashley", "scroll", "relate", "divisions", "swim", "wages", "additionally", "suffer", "forests",
	"fellowship", "nano", "invalid", "concerts", "martial", "males", "victorian", "retain", "execute", "tunnel", "genres", "cambodia",
	"patents", "copyrights", "yn", "chaos", "lithuania", "mastercard", "wheat", "chronicles", "obtaining", "beaver", "updating", "distribute",
	"readings", "decorative", "kijiji", "confused", "compiler", "enlargement", "eagles", "bases", "vii", "accused", "bee", "campaigns",
	"unity", "loud", "conjunction", "bride", "rats", "defines", "airports", "instances", "indigenous", "begun", "brunette", "packets",
	"anchor", "socks", "validation", "parade", "corruption", "stat", "trigger", "incentives", "cholesterol", "gathered", "essex", "slovenia",
	"notified", "differential", "beaches", "folders", "dramatic", "surfaces", "routers", "cruz", "pendant", "dresses", "baptist", "scientist",
	"starsmerchant", "hiring", "clocks", "arthritis", "bios", "females", "wallace", "nevertheless", "reflects", "taxation", "fever", "cuisine",
	"surely", "practitioners", "transcript", "myspace", "theorem", "inflation", "thee", "ruth", "pray", "stylus", "compounds", "pope",
	"drums", "contracting", "arnold", "structured", "reasonably", "jeep", "chicks", "bare", "hung", "cattle", "mba", "radical",
	"graduates", "rover", "recommends", "controlling", "treasure", "reload", "distributors", "flame", "tanks", "assuming", "monetary", "elderly",
	"pit", "arlington", "mono", "particles", "floating", "extraordinary", "tile", "indicating", "bolivia", "spell", "hottest", "stevens",
	"coordinate", "kuwait", "exclusively", "emily", "alleged", "limitation", "widescreen", "compile", "webster", "struck", "illustration", "plymouth",
	"warnings", "construct", "apps", "inquiries", "bridal", "annex", "mag", "inspiration", "tribal", "curious", "affecting", "freight",
	"rebate", "meetup", "eclipse", "sudan", "downloading", "rec", "shuttle", "aggregate", "stunning", "cycles", "affects", "forecasts",
	"detect", "actively", "ciao", "ampland", "knee", "prep", "complicated", "chem", "fastest", "butler", "shopzilla", "injured",
	"decorating", "payroll", "cookbook", "expressions", "ton", "courier", "uploaded", "shakespeare", "hints", "collapse", "americas", "connectors",
	"unlikely", "oe", "gif", "pros", "conflicts", "techno", "beverage", "wired", "elvis", "immune", "latvia", "travelers",
	"forestry", "barriers", "cant", "infected", "offerings", "martha", "genesis", "barrier", "argue", "incorrect", "trains", "metals",
	"bicycle", "furnishings", "letting", "arise", "guatemala", "celtic", "thereby", "irc", "jamie", "particle", "perception", "minerals",
	"advise", "humidity", "bottles", "boxing", "wy", "bangkok", "renaissance", "pathology", "sara", "bra", "ordinance", "hughes",
	"photographers", "infections", "jeffrey", "chess", "operates", "brisbane", "configured", "survive", "oscar", "festivals", "menus", "joan",
	"possibilities", "duck", "reveal", "canal", "amino", "phi", "contributing", "herbs", "clinics", "manitoba", "analytical", "missions",
	"watson", "lying", "costumes", "strict", "dive", "saddam", "circulation", "drill", "offense", "bryan", "cet", "protest",
	"assumption", "jerusalem", "hobby", "tries", "transexuales", "invention", "nickname", "fiji", "technician", "inline", "executives", "enquiries",
	"washing", "audi", "staffing", "cognitive", "exploring", "trick", "enquiry", "closure", "timber", "volt", "intense", "div",
	"playlist", "registrar", "showers", "supporters", "ruling", "steady", "dirt", "statutes", "withdrawal", "myers", "drops", "predicted",
	"wider", "saskatchewan", "cancellation", "plugins", "enrolled", "sensors", "ministers", "publicly", "hourly", "blame", "geneva", "freebsd",
	"veterinary", "acer", "prostores", "reseller", "dist", "handed", "suffered", "intake", "informal", "relevance", "incentive", "butterfly",
	"tucson", "mechanics", "heavily", "swingers", "fifty", "headers", "mistakes", "numerical", "ons", "geek", "uncle", "defining",
	"counting", "reflection", "sink", "accompanied", "assure", "invitation", "devoted", "princeton", "jacob", "sodium", "randy", "spirituality",
	"hormone", "meanwhile", "proprietary", "timothy", "childrens", "brick", "grip", "naval", "thumbzilla", "medieval", "porcelain", "avi",
	"bridges", "pichunter", "captured", "watt", "thehun", "decent", "casting", "dayton", "translated", "shortly", "cameron", "columnists",
	"pins", "carlos", "reno", "donna", "andreas", "diploma", "cabin", "innocent", "scanning", "ide", "consensus", "polo",
	"valium", "copying", "delivering", "cordless", "patricia", "horn", "eddie", "uganda", "fired", "journalism", "prot", "trivia",
	"adidas", "perth", "frog", "grammar", "intention", "syria", "disagree", "klein", "harvey", "tires", "logs", "undertaken",
	"hazard", "retro", "leo", "statewide", "semiconductor", "gregory", "episodes", "boolean", "circular", "anger", "diy", "mainland",
	"illustrations", "suits", "chances", "interact", "snap", "happiness", "arg", "substantially", "bizarre", "glenn", "auckland", "olympics",
	"fruits", "identifier", "geo", "ribbon", "calculations", "doe", "jpeg", "conducting", "startup", "suzuki", "trinidad", "ati",
	"kissing", "wal", "handy", "swap", "exempt", "crops", "reduces", "accomplished", "calculators", "geometry", "impression", "abs",
	"slovakia", "flip", "correlation", "gorgeous", "capitol", "sim", "dishes", "rna", "barbados", "chrysler", "nervous", "refuse",
	"extends", "fragrance", "mcdonald", "replica", "plumbing", "brussels", "tribe", "neighbors", "trades", "superb", "buzz", "transparent",
	"rid", "trinity", "charleston", "handled", "legends", "boom", "calm", "champions", "floors", "selections", "projectors", "inappropriate",
	"exhaust", "comparing", "shanghai", "speaks", "burton", "vocational", "davidson", "copied", "scotia", "farming", "gibson", "pharmacies",
	"fork", "troy", "roller", "introducing", "batch", "organize", "appreciated", "alter", "nicole", "latino", "ghana", "edges",
	"uc", "mixing", "handles", "skilled", "fitted", "albuquerque", "harmony", "distinguished", "asthma", "projected", "assumptions", "shareholders",
	"twins", "developmental", "rip", "zope", "regulated", "triangle", "amend", "anticipated", "oriental", "reward", "windsor", "zambia",
	"completing", "buf", "hydrogen", "webshots", "sprint", "comparable", "chick", "advocate", "sims", "confusion", "copyrighted", "tray",
	"inputs", "warranties", "genome", "documented", "thong", "medal", "paperbacks", "coaches", "vessels", "walks", "sol", "keyboards",
	"sage", "knives", "eco", "vulnerable", "arrange", "artistic", "bat", "honors", "booth", "indie", "reflected", "unified",
	"bones", "breed", "detector", "ignored", "polar", "fallen", "precise", "sussex", "respiratory", "notifications", "msgid", "transexual",
	"mainstream", "invoice", "evaluating", "lip", "subcommittee", "sap", "gather", "suse", "maternity", "backed", "alfred", "colonial",
	"carey", "motels", "forming", "embassy", "cave", "journalists", "danny", "rebecca", "slight", "proceeds", "indirect", "amongst",
	"wool", "foundations", "arrest", "volleyball", "adipex", "horizon", "nu", "deeply", "toolbox", "ict", "marina", "liabilities",
	"prizes", "bosnia", "browsers", "decreased", "patio", "tolerance", "surfing", "creativity", "lloyd", "describing", "optics", "pursue",
	"lightning", "overcome", "eyed", "ou", "quotations", "grab", "inspector", "attract", "brighton", "beans", "bookmarks", "ellis",
	"disable", "snake", "succeed", "leonard", "lending", "oops", "reminder", "xi", "searched", "behavioral", "riverside", "bathrooms",
	"plains", "sku", "raymond", "insights", "abilities", "initiated", "sullivan", "za", "midwest", "karaoke", "trap", "lonely",
	"fool", "ve", "nonprofit", "lancaster", "suspended", "hereby", "observe", "julia", "containers", "attitudes", "karl", "berry",
	"collar", "simultaneously", "racial", "integrate", "bermuda", "amanda", "sociology", "mobiles", "screenshot", "exhibitions", "kelkoo", "confident",
	"retrieved", "exhibits", "officially", "consortium", "dies", "terrace", "bacteria", "replied", "seafood", "novels", "recipients", "ought",
	"delicious", "traditions", "safely", "finite", "kidney", "periodically", "fixes", "sends", "durable", "mazda", "allied", "throws",
	"moisture", "hungarian", "roster", "referring", "symantec", "spencer", "wichita", "nasdaq", "uruguay", "ooo", "transform", "timer",
	"tablets", "tuning", "educators", "tyler", "futures", "vegetable", "verse", "highs", "humanities", "independently", "wanting", "custody",
	"scratch", "launches", "ipaq", "alignment", "henderson", "britannica", "comm", "ellen", "competitors", "rocket", "aye", "bullet",
	"towers", "racks", "lace", "nasty", "visibility", "latitude", "consciousness", "ste", "tumor", "deposits", "beverly", "mistress",
	"encounter", "trustees", "watts", "duncan", "reprints", "hart", "bernard", "resolutions", "ment", "accessing", "forty", "tubes",
	"attempted", "col", "midlands", "floyd", "ronald", "analysts", "queue", "trance", "locale", "nicholas", "biol", "yu",
	"bundle", "hammer", "witnesses", "runner", "rows", "administered", "notion", "skins", "mailed", "oc", "fujitsu", "spelling",
	"arctic", "exams", "rewards", "beneath", "strengthen", "aj", "frederick", "medicaid", "treo", "infrared", "seventh", "gods",
	"une", "welsh", "belly", "aggressive", "tex", "advertisements", "quarters", "stolen", "cia", "sublimedirectory", "soonest", "haiti",
	"disturbed", "determines", "sculpture", "poly", "ears", "dod", "fist", "naturals", "neo", "motivation", "lenders", "pharmacology",
	"fitting", "fixtures", "bloggers", "mere", "agrees", "passengers", "quantities", "petersburg", "consistently", "powerpoint", "cons", "surplus",
	"elder", "sonic", "obituaries", "cheers", "dig", "taxi", "punishment", "appreciation", "subsequently", "om", "belarus", "nat",
	"zoning", "gravity", "providence", "thumb", "restriction", "incorporate", "backgrounds", "treasurer", "guitars", "essence", "flooring", "lightweight",
	"ethiopia", "mighty", "athletes", "humanity", "transcription", "holmes", "complications", "scholars", "dpi", "scripting", "gis", "remembered",
	"galaxy", "chester", "snapshot", "caring", "loc", "worn", "synthetic", "shaw", "segments", "testament", "expo", "dominant",
	"twist", "specifics", "itunes", "stomach", "partially", "buried", "newbie", "minimize", "darwin", "ranks", "wilderness", "debut",
	"generations", "tournaments", "bradley", "deny", "anatomy", "bali", "judy", "sponsorship", "headphones", "fraction", "trio", "proceeding",
	"cube", "defects", "volkswagen", "uncertainty", "breakdown", "milton", "marker", "reconstruction", "subsidiary", "strengths", "clarity", "rugs",
	"sandra", "adelaide", "encouraging", "furnished", "monaco", "settled", "folding", "emirates", "terrorists", "airfare", "comparisons", "beneficial",
	"distributions", "vaccine", "belize", "fate", "viewpicture", "promised", "volvo", "penny", "robust", "bookings", "threatened", "minolta",
	"republicans", "discusses", "gui", "porter", "gras", "jungle", "ver", "responded", "rim", "abstracts", "zen", "ivory",
	"alpine", "dis", "prediction", "pharmaceuticals", "andale", "fabulous", "remix", "alias", "thesaurus", "individually", "battlefield", "literally",
	"newer", "kay", "ecological", "spice", "oval", "implies", "soma", "ser", "cooler", "appraisal", "consisting", "maritime",
	"periodic", "submitting", "overhead", "ascii", "prospect", "shipment", "breeding", "citations", "geographical", "donor", "mozambique", "tension",
	"href", "benz", "trash", "shapes", "wifi", "tier", "earl", "manor", "envelope", "diane", "homeland", "disclaimers",
	"championships", "excluded", "andrea", "breeds", "rapids", "disco", "sheffield", "bailey", "aus", "endif", "finishing", "emotions",
	"wellington", "incoming", "prospects", "lexmark", "cleaners", "bulgarian", "hwy", "eternal", "cashiers", "guam", "cite", "aboriginal",
	"remarkable", "rotation", "nam", "preventing", "productive", "boulevard", "eugene", "ix", "metric", "compliant", "minus", "penalties",
	"bennett", "imagination", "hotmail", "refurbished", "joshua", "armenia", "varied", "grande", "closest", "activated", "actress", "mess",
	"conferencing", "assign", "armstrong", "politicians", "trackbacks", "lit", "accommodate", "tigers", "aurora", "una", "slides", "milan",
	"premiere", "lender", "villages", "shade", "chorus", "christine", "rhythm", "digit", "argued", "dietary", "symphony", "clarke",
	"sudden", "accepting", "precipitation", "marilyn", "lions", "findlaw", "ada", "pools", "lyric", "claire", "isolation", "speeds",
	"sustained", "matched", "approximate", "rope", "carroll", "rational", "programmer", "fighters", "chambers", "dump", "greetings", "inherited",
	"warming", "incomplete", "vocals", "chronicle", "fountain", "chubby", "grave", "legitimate", "biographies", "burner", "yrs", "foo",
	"investigator", "gba", "plaintiff", "finnish", "gentle", "prisoners", "deeper", "muslims", "hose", "mediterranean", "nightlife", "footage",
	"howto", "worthy", "reveals", "architects", "saints", "entrepreneur", "carries", "sig", "freelance", "duo", "excessive", "devon",
	"screensaver", "helena", "saves", "regarded", "valuation", "unexpected", "cigarette", "fog", "characteristic", "marion", "lobby", "egyptian",
	"tunisia", "metallica", "outlined", "consequently", "headline", "treating", "punch", "appointments", "cowboy", "narrative", "bahrain", "enormous",
	"karma", "consist", "betty", "queens", "academics", "pubs", "quantitative", "lucas", "screensavers", "subdivision", "tribes", "vip",
	"defeat", "clicks", "distinction", "honduras", "naughty", "hazards", "insured", "harper", "livestock", "mardi", "exemption", "tenant",
	"sustainability", "cabinets", "tattoo", "shake", "algebra", "shadows", "holly", "formatting", "silly", "nutritional", "mercy", "hartford",
	"freely", "marcus", "sunrise", "wrapping", "mild", "fur", "nicaragua", "weblogs", "timeline", "tar", "belongs", "readily",
	"affiliation", "soc", "fence", "nudist", "infinite", "diana", "ensures", "relatives", "lindsay", "clan", "legally", "shame",
	"satisfactory", "revolutionary", "bracelets", "sync", "civilian", "telephony", "mesa", "fatal", "remedy", "realtors", "breathing", "briefly",
	"thickness", "adjustments", "graphical", "genius", "discussing", "aerospace", "fighter", "meaningful", "flesh", "retreat", "adapted", "barely",
	"wherever", "estates", "rug", "democrat", "borough", "maintains", "failing", "shortcuts", "ka", "retained", "voyeurweb", "pamela",
	"andrews", "marble", "extending", "jesse", "specifies", "hull", "logitech", "surrey", "briefing", "belkin", "dem", "accreditation",
	"wav", "blackberry", "highland", "meditation", "modular", "microphone", "macedonia", "combining", "brandon", "instrumental", "giants", "organizing",
	"shed", "balloon", "moderators", "winston", "memo", "ham", "solved", "tide", "kazakhstan", "hawaiian", "standings", "partition",
	"invisible", "gratuit", "consoles", "funk", "fbi", "qatar", "magnet", "translations", "porsche", "cayman", "jaguar", "reel",
	"sheer", "commodity", "posing", "kilometers", "bind", "thanksgiving", "rand", "hopkins", "urgent", "guarantees", "infants", "gothic",
	"cylinder", "buck", "indication", "eh", "congratulations", "tba", "cohen", "sie", "usgs", "puppy", "kathy", "acre",
	"graphs", "surround", "cigarettes", "revenge", "expires", "lows", "controllers", "aqua", "chen", "emma", "consultancy", "finances",
	"accepts", "enjoying", "conventions", "eva", "patrol", "smell", "pest", "italiano", "coordinates", "rca", "carnival", "roughly",
	"sticker", "promises", "responding", "reef", "physically", "divide", "stakeholders", "hydrocodone", "consecutive", "cornell", "satin", "bon",
	"deserve", "attempting", "mailto", "promo", "representations", "chan", "worried", "tunes", "garbage", "competing", "combines", "mas",
	"beth", "bradford", "len", "phrases", "kai", "peninsula", "chelsea", "boring", "reynolds", "dom", "jill", "accurately",
	"speeches", "reaches", "schema", "considers", "sofa", "catalogs", "ministries", "vacancies", "quizzes", "parliamentary", "obj", "prefix",
	"lucia", "savannah", "barrel", "typing", "nerve", "dans", "planets", "deficit", "boulder", "pointing", "renew", "coupled",
	"viii", "myanmar", "metadata", "harold", "circuits", "floppy", "texture", "handbags", "jar", "ev", "somerset", "incurred",
	"acknowledge", "thoroughly", "antigua", "nottingham", "thunder", "tent", "caution", "identifies", "questionnaire", "qualification", "locks", "modelling",
	"namely", "miniature", "dept", "hack", "dare", "euros", "interstate", "pirates", "aerial", "hawk", "consequence", "rebel",
	"systematic", "perceived", "origins", "hired", "makeup", "textile", "lamb", "madagascar", "nathan", "tobago", "presenting", "cos",
	"troubleshooting", "uzbekistan", "indexes", "pac", "erp", "centuries", "magnitude", "ui", "richardson", "hindu", "fragrances", "vocabulary",
	"licking", "fundraising", "markers", "weights", "albania", "geological", "assessing", "lasting", "wicked", "eds", "introduces", "kills",
	"roommate", "webcams", "pushed", "webmasters", "ro", "computational", "acdbentity", "participated", "junk", "handhelds", "wax", "lucy",
	"answering", "hans", "impressed", "slope", "reggae", "failures", "poet", "conspiracy", "surname", "theology", "nails", "evident",
	"whats", "rides", "rehab", "epic", "saturn", "organizer", "nut", "allergy", "sake", "twisted", "combinations", "preceding",
	"merit", "enzyme", "cumulative", "zshops", "planes", "edmonton", "tackle", "disks", "condo", "pokemon", "amplifier", "ambien",
	"arbitrary", "prominent", "retrieve", "lexington", "vernon", "sans", "worldcat", "titanium", "irs", "builds", "contacted", "shaft",
	"lean", "recorders", "occasional", "leslie", "casio", "deutsche", "ana", "postings", "innovations", "kitty", "postcards", "dude",
	"drain", "monte", "fires", "algeria", "blessed", "luis", "reviewing", "cardiff", "cornwall", "favors", "potato", "panic",
	"explicitly", "sticks", "leone", "transsexual", "ez", "citizenship", "excuse", "reforms", "basement", "onion", "strand", "sandwich",
	"uw", "lawsuit", "alto", "informative", "girlfriend", "bloomberg", "cheque", "hierarchy", "influenced", "banners", "reject", "eau",
	"abandoned", "circles", "italic", "beats", "merry", "mil", "scuba", "gore", "complement", "cult", "dash", "passive",
	"mauritius", "valued", "cage", "checklist", "requesting", "courage", "verde", "lauderdale", "scenarios", "hitachi", "divx", "extraction",
	"batman", "elevation", "hearings", "coleman", "hugh", "lap", "utilization", "beverages", "calibration", "jake", "eval", "efficiently",
	"anaheim", "ping", "textbook", "dried", "entertaining", "prerequisite", "luther", "frontier", "settle", "stopping", "refugees", "knights",
	"hypothesis", "palmer", "medicines", "flux", "derby", "sao", "peaceful", "altered", "pontiac", "regression", "doctrine", "scenic",
	"trainers", "muze", "enhancements", "renewable", "intersection", "passwords", "sewing", "consistency", "collectors", "conclude", "munich", "oman",
	"celebs", "propose", "azerbaijan", "lighter", "rage", "adsl", "uh", "prix", "astrology", "pavilion", "tactics", "trusts",
	"occurring", "supplemental", "travelling", "talented", "annie", "pillow", "induction", "derek", "precisely", "shorter", "harley", "spreading",
	"provinces", "relying", "finals", "paraguay", "steal", "parcel", "refined", "bo", "fifteen", "widespread", "incidence", "fears",
	"predict", "boutique", "acrylic", "rolled", "tuner", "avon", "incidents", "peterson", "rays", "asn", "shannon", "toddler",
	"enhancing", "flavor", "alike", "walt", "homeless", "horrible", "metallic", "acne", "blocked", "interference", "warriors", "palestine",
	"listprice", "libs", "undo", "cadillac", "atmospheric", "malawi", "sagem", "knowledgestorm", "dana", "halo", "curtis", "parental",
	"referenced", "strikes", "lesser", "publicity", "marathon", "ant", "proposition", "gays", "pressing", "gasoline", "apt", "dressed",
	"belfast", "exec", "dealt", "niagara", "inf", "eos", "warcraft", "charms", "catalyst", "trader", "bucks", "allowance",
	"denial", "uri", "designation", "thrown", "prepaid", "raises", "gem", "duplicate", "electro", "criterion", "badge", "wrist",
	"civilization", "analyzed", "vietnamese", "heath", "tremendous", "ballot", "lexus", "varying", "remedies", "validity", "trustee", "maui",
	"weighted", "angola", "performs", "plastics", "realm", "jenny", "helmet", "salaries", "postcard", "elephant", "yemen", "encountered",
	"tsunami", "scholar", "nickel", "internationally", "surrounded", "psi", "buses", "expedia", "geology", "creatures", "coating", "commented",
	"wallet", "cleared", "smilies", "vids", "accomplish", "boating", "drainage", "shakira", "corners", "broader", "vegetarian", "rouge",
	"yeast", "yale", "newfoundland", "pas", "clearing", "investigated", "ambassador", "coated", "intend", "stephanie", "contacting", "vegetation",
	"doom", "findarticles", "louise", "kenny", "specially", "owen", "routines", "hitting", "yukon", "beings", "bite", "issn",
	"aquatic", "reliance", "habits", "striking", "myth", "infectious", "podcasts", "singh", "gig", "gilbert", "sas", "ferrari",
	"continuity", "brook", "fu", "outputs", "phenomenon", "ensemble", "insulin", "assured", "biblical", "weed", "conscious", "accent",
	"mysimon", "eleven", "wives", "ambient", "utilize", "mileage", "oecd", "prostate", "adaptor", "auburn", "unlock", "hyundai",
	"pledge", "angela", "relates", "nitrogen", "xerox", "dice", "merger", "softball", "referrals", "quad", "dock", "differently",
	"firewire", "mods", "nextel", "framing", "musician", "blocking", "rwanda", "sorts", "integrating", "vsnet", "limiting", "dispatch",
	"revisions", "papua", "restored", "hint", "armor", "riders", "chargers", "remark", "dozens", "varies", "msie", "reasoning",
	"liz", "rendered", "picking", "charitable", "guards", "annotated", "convinced", "openings", "buys", "burlington", "replacing", "researcher",
	"watershed", "councils", "occupations", "acknowledged", "kruger", "pockets", "granny", "pork", "zu", "equilibrium", "viral", "inquire",
	"pipes", "characterized", "laden", "aruba", "cottages", "realtor", "merge", "privilege", "edgar", "develops", "qualifying", "chassis",
	"dubai", "estimation", "barn", "pushing", "fleece", "pediatric", "boc", "fare", "asus", "pierce", "allan", "dressing",
	"techrepublic", "sperm", "bald", "filme", "craps", "fuji", "frost", "leon", "institutes", "mold", "dame", "fo",
	"sally", "yacht", "tracy", "prefers", "drilling", "brochures", "herb", "alot", "ate", "breach", "whale", "traveller",
	"appropriations", "suspected", "tomatoes", "benchmark", "beginners", "instructors", "highlighted", "bedford", "stationery", "idle", "mustang", "unauthorized",
	"clusters", "antibody", "competent", "momentum", "fin", "wiring", "io", "pastor", "mud", "calvin", "uni", "shark",
	"contributor", "demonstrates", "phases", "grateful", "emerald", "gradually", "laughing", "grows", "cliff", "desirable", "tract", "ul",
	"ballet", "ol", "journalist", "abraham", "bumper", "afterwards", "webpage", "religions", "garlic", "hostels", "shine", "senegal",
	"explosion", "banned", "wendy", "briefs", "signatures", "diffs", "cove", "mumbai", "ozone", "disciplines", "casa", "mu",
	"daughters", "conversations", "radios", "tariff", "nvidia", "opponent", "pasta", "simplified", "muscles", "serum", "wrapped", "swift",
	"motherboard", "runtime", "inbox", "focal", "bibliographic", "eden", "distant", "incl", "champagne", "ala", "decimal", "deviation",
	"superintendent", "dip", "samba", "hostel", "housewives", "employ", "mongolia", "penguin", "magical", "influences", "inspections", "irrigation",
	"miracle", "manually", "reprint", "reid", "hydraulic", "centered", "robertson", "flex", "yearly", "penetration", "wound", "belle",
	"rosa", "conviction", "hash", "omissions", "writings", "hamburg", "lazy", "retrieval", "qualities", "cindy", "fathers", "carb",
	"charging", "cas", "marvel", "lined", "cio", "dow", "prototype", "importantly", "petite", "apparatus", "upc", "terrain",
	"dui", "pens", "explaining", "yen", "strips", "gossip", "rangers", "nomination", "empirical", "rotary", "worm", "dependence",
	"discrete", "beginner", "boxed", "lid", "sexuality", "polyester", "cubic", "deaf", "commitments", "suggesting", "sapphire", "kinase",
	"skirts", "mats", "remainder", "crawford", "labeled", "privileges", "televisions", "specializing", "marking", "commodities", "serbia", "sheriff",
	"declined", "guyana", "blah", "mime", "neighbor", "motorcycles", "elect", "highways", "thinkpad", "concentrate", "intimate", "reproductive",
	"preston", "deadly", "feof", "bunny", "chevy", "molecules", "rounds", "longest", "refrigerator", "tions", "intervals", "sentences",
	"dentists", "usda", "exclusion", "workstation", "holocaust", "keen", "flyer", "peas", "dosage", "receivers", "urls", "disposition",
	"variance", "navigator", "investigators", "cameroon", "baking", "marijuana", "adaptive", "computed", "needle", "baths", "enb", "cathedral",
	"brakes", "og", "nirvana", "ko", "fairfield", "owns", "til", "invision", "sticky", "destiny", "generous", "madness",
	"emacs", "climb", "blowing", "fascinating", "landscapes", "heated", "lafayette", "jackie", "wto", "computation", "hay", "cardiovascular",
	"sparc", "cardiac", "salvation", "dover", "adrian", "predictions", "accompanying", "vatican", "brutal", "learners", "selective", "arbitration",
	"configuring", "token", "editorials", "zinc", "sacrifice", "seekers", "guru", "isa", "removable", "convergence", "yields", "gibraltar",
	"levy", "suited", "numeric", "anthropology", "skating", "aberdeen", "emperor", "grad", "malpractice", "dylan", "bras", "belts",
	"blacks", "educated", "rebates", "reporters", "burke", "proudly", "pix", "necessity", "rendering", "mic", "inserted", "pulling",
	"basename", "kyle", "obesity", "curves", "suburban", "touring", "clara", "vertex", "hepatitis", "nationally", "tomato", "andorra",
	"waterproof", "expired", "travels", "flush", "waiver", "pale", "specialties", "hayes", "humanitarian", "invitations", "functioning", "delight",
	"survivor", "garcia", "cingular", "economies", "alexandria", "bacterial", "moses", "counted", "undertake", "declare", "continuously", "johns",
	"valves", "gaps", "impaired", "achievements", "donors", "tear", "jewel", "teddy", "convertible", "ata", "teaches", "ventures",
	"nil", "bufing", "stranger", "tragedy", "julian", "nest", "pam", "dryer", "painful", "velvet", "tribunal", "ruled",
	"nato", "pensions", "prayers", "funky", "secretariat", "nowhere", "cop", "paragraphs", "gale", "joins", "adolescent", "nominations",
	"wesley", "dim", "lately", "cancelled", "scary", "mattress", "mpegs", "brunei", "likewise", "banana", "introductory", "slovak",
	"cakes", "stan", "reservoir", "occurrence", "idol", "mixer", "remind", "worcester", "demographic", "charming", "mai", "tooth",
	"disciplinary", "annoying", "respected", "stays", "disclose", "affair", "drove", "washer", "upset", "restrict", "springer", "beside",
	"mines", "portraits", "rebound", "logan", "mentor", "interpreted", "evaluations", "baghdad", "elimination", "metres", "hypothetical", "immigrants",
	"complimentary", "helicopter", "pencil", "freeze", "performer", "abu", "titled", "commissions", "sphere", "powerseller", "moss", "ratios",
	"concord", "graduated", "endorsed", "ty", "surprising", "walnut", "lance", "ladder", "italia", "unnecessary", "dramatically", "liberia",
	"sherman", "cork", "maximize", "hansen", "senators", "workout", "mali", "yugoslavia", "bleeding", "characterization", "colon", "likelihood",
	"lanes", "purse", "fundamentals", "contamination", "endangered", "compromise", "optimize", "stating", "dome", "caroline", "leu", "expiration",
	"namespace", "align", "peripheral", "bless", "engaging", "negotiation", "opponents", "triumph", "nominated", "confidentiality", "electoral", "changelog",
	"welding", "deferred", "alternatively", "heel", "alloy", "condos", "plots", "polished", "yang", "gently", "greensboro", "tulsa",
	"locking", "casey", "controversial", "draws", "fridge", "blanket", "bloom", "simpsons", "lou", "elliott", "recovered", "fraser",
	"justify", "upgrading", "blades", "loops", "surge", "frontpage", "trauma", "aw", "tahoe", "advert", "possess", "demanding",
	"defensive", "sip", "flashers", "subaru", "forbidden", "vanilla", "programmers", "monitored", "installations", "deutschland", "picnic", "souls",
	"arrivals", "spank", "practitioner", "motivated", "smithsonian", "hollow", "vault", "securely", "examining", "fioricet", "groove", "revelation",
	"pursuit", "delegation", "wires", "dictionaries", "mails", "backing", "greenhouse", "sleeps", "blake", "transparency", "dee", "travis",
	"endless", "figured", "orbit", "currencies", "niger", "bacon", "survivors", "positioning", "heater", "colony", "cannon", "circus",
	"promoted", "forbes", "mae", "moldova", "mel", "descending", "paxil", "spine", "trout", "enclosed", "feat", "temporarily",
	"cooked", "thriller", "transmit", "apnic", "fatty", "gerald", "pressed", "frequencies", "scanned", "reflections", "hunger", "mariah",
	"sic", "municipality", "usps", "joyce", "detective", "surgeon", "cement", "experiencing", "fireplace", "endorsement", "planners", "disputes",
	"textiles", "missile", "intranet", "closes", "seq", "psychiatry", "persistent", "deborah", "conf", "marco", "assists", "summaries",
	"glow", "gabriel", "auditor", "wma", "aquarium", "violin", "prophet", "cir", "bracket", "looksmart", "isaac", "oxide",
	"oaks", "magnificent", "erik", "colleague", "naples", "promptly", "modems", "adaptation", "hu", "harmful", "paintball", "prozac",
	"sexually", "enclosure", "acm", "dividend", "newark", "paso", "glucose", "phantom", "norm", "playback", "supervisors", "westminster",
	"turtle", "ips", "distances", "absorption", "treasures", "warned", "neural", "ware", "fossil", "mia", "hometown", "badly",
	"transcripts", "apollo", "wan", "disappointed", "persian", "continually", "communist", "collectible", "handmade", "greene", "entrepreneurs", "robots",
	"grenada", "creations", "jade", "scoop", "acquisitions", "foul", "keno", "earning", "mailman", "sanyo", "nested", "biodiversity",
	"excitement", "somalia", "movers", "verbal", "blink", "presently", "seas", "carlo", "workflow", "mysterious", "novelty", "bryant",
	"tiles", "voyuer", "librarian", "subsidiaries", "switched", "stockholm", "tamil", "garmin", "ru", "pose", "fuzzy", "indonesian",
	"grams", "therapist", "richards", "mrna", "budgets", "toolkit", "promising", "relaxation", "goat", "render", "carmen", "ira",
	"sen", "thereafter", "hardwood", "erotica", "temporal", "sail", "forge", "commissioners", "dense", "forwarding", "awful", "nightmare",
	"airplane", "reductions", "southampton", "istanbul", "impose", "organisms", "sega", "telescope", "viewers", "asbestos", "portsmouth", "cdna",
	"meyer", "enters", "pod", "savage", "advancement", "wu", "harassment", "willow", "resumes", "bolt", "gage", "throwing",
	"existed", "generators", "lu", "wagon", "barbie", "dat", "soa", "knock", "urge", "generates", "potatoes", "thorough",
	"replication", "inexpensive", "kurt", "receptors", "peers", "roland", "optimum", "neon", "interventions", "quilt", "huntington", "creature",
	"ours", "mounts", "syracuse", "internship", "lone", "refresh", "aluminium", "snowboard", "beastality", "webcast", "michel", "evanescence",
	"subtle", "coordinated", "notre", "shipments", "maldives", "stripes", "firmware", "antarctica", "cope", "shepherd", "canberra", "cradle",
	"chancellor", "mambo", "lime", "kirk", "flour", "controversy", "legendary", "bool", "sympathy", "choir", "avoiding", "beautifully",
	"blond", "expects", "cho", "jumping", "fabrics", "antibodies", "polymer", "hygiene", "wit", "poultry", "virtue", "burst",
	"examinations", "surgeons", "bouquet", "immunology", "promotes", "mandate", "wiley", "departmental", "spas", "ind", "corpus", "johnston",
	"terminology", "gentleman", "fibre", "reproduce", "convicted", "shades", "jets", "indices", "roommates", "adware", "qui", "intl",
	"threatening", "spokesman", "zoloft", "activists", "frankfurt", "prisoner", "daisy", "halifax", "encourages", "ultram", "cursor", "assembled",
	"earliest", "donated", "stuffed", "restructuring", "insects", "terminals", "crude", "morrison", "maiden", "simulations", "sufficiently", "examines",
	"myrtle", "bored", "cleanup", "yarn", "knit", "conditional", "mug", "crossword", "bother", "budapest", "conceptual", "knitting",
	"bhutan", "liechtenstein", "mating", "compute", "redhead", "arrives", "translator", "automobiles", "tractor", "allah", "continent", "ob",
	"unwrap", "fares", "longitude", "resist", "challenged", "telecharger", "hoped", "pike", "safer", "insertion", "instrumentation", "ids",
	"hugo", "wagner", "constraint", "groundwater", "touched", "strengthening", "cologne", "gzip", "wishing", "smallest", "insulation", "newman",
	"marsh", "ricky", "theta", "infringement", "bent", "laos", "subjective", "monsters", "asylum", "lightbox", "robbie", "stake",
	"cocktail", "outlets", "swaziland", "varieties", "arbor", "mediawiki", "configurations", "poison",
]


## Frequency rank of each base word (0 = most common). Curated words come
## first in BASE_WORDS and are common by construction; the google-10k tail
## keeps its published frequency order. Drives the common-word tie-break in
## _candidate_score ("teh" -> "the", never "ten").
var _base_rank: Dictionary = {}


func _init() -> void:
	var rank := 0
	for w in BASE_WORDS:
		if not _base_words.has(w):
			_base_words[w] = true
			_base_rank[w] = rank
			rank += 1
	load_dict()


# --- dictionary queries -------------------------------------------------------

func is_known(word: String) -> bool:
	var w := _clean(word)
	if w == "":
		return true
	return _base_words.has(w) or _learned.has(w)


func is_learned(word: String) -> bool:
	return _learned.has(_clean(word))


func learned_words() -> Array:
	var out: Array = _learned.keys()
	out.sort()
	return out


func base_word_count() -> int:
	return _base_words.size()


func slang_affinity() -> float:
	return _slang_affinity


func word_frequency(word: String) -> int:
	return int(_word_freq.get(_clean(word), 0))


func _clean(word: String) -> String:
	return word.to_lower().strip_edges()


# --- learning: every typed word feeds the personal model -----------------------
## Call for each completed word. Updates frequency, bigrams, slang affinity,
## unknown-word tracking, and the bigram chain. Returns "prompt" when the
## "Add word?" dialog should show, "learned" when auto-learned, "" otherwise.

func note_word_typed(word: String, typed_word: String = "") -> String:
	var w := _clean(word)
	if w == "":
		return ""
	# The originally typed word (before any autocorrect rewrite). Learning
	# must track what the user TYPED, not just what ended up in the text —
	# otherwise a correction swallows learning (Jeremy 2026-10-05: "butt"
	# typed repeatedly never learned because only "but" was recorded).
	var t := _clean(typed_word)
	if t == "":
		t = w
	# Frequency: trust what the user actually types — both the final word
	# and the raw typed word (so an adopted "typo" stops being corrected).
	_word_freq[w] = int(_word_freq.get(w, 0)) + 1
	if t != w:
		_word_freq[t] = int(_word_freq.get(t, 0)) + 1
	if _word_freq.size() > MAX_WORD_FREQ:
		_trim_word_freq()
	# Bigram: what follows what (final word — that's what's in the text).
	if _last_word != "":
		var key := _last_word + "|" + w
		_bigrams[key] = int(_bigrams.get(key, 0)) + 1
		if _bigrams.size() > MAX_BIGRAMS:
			_trim_bigrams()
	_last_word = w
	# Style: slang markers raise affinity, formal words lower it slightly.
	if w in SLANG_MARKERS:
		_slang_affinity = minf(1.0, _slang_affinity + 0.08)
	elif w.length() > 6 and not (w in _base_words) and not (w in _learned):
		pass  # unknown long words handled below, don't touch affinity
	else:
		_slang_affinity = maxf(0.0, _slang_affinity - 0.004)
	# Unknown-word learning trigger — on the final word AND the typed word.
	var res := _track_unknown(w)
	if t != w:
		var r2 := _track_unknown(t)
		if r2 != "":
			res = r2
	return res


## Reset the bigram chain (sentence end, field cleared, etc.).
func note_sentence_end() -> void:
	_last_word = ""


func _track_unknown(w: String) -> String:
	if w == "" or is_known(w):
		return ""
	if w.length() < 2:
		return ""
	# Only letters, apostrophes, hyphens — skip numbers and junk.
	for i in w.length():
		var ch := w[i]
		if not ((ch >= "a" and ch <= "z") or ch == "'" or ch == "-"):
			return ""
	# Fast path: if the user already types it a lot, it's basically theirs.
	var count := int(_unknown_counts.get(w, 0)) + 1
	_unknown_counts[w] = count
	if count >= LEARN_THRESHOLD:
		_unknown_counts.erase(w)
		last_prompt_word = w
		if auto_learn:
			_learned[w] = true
			_mark_candidates_dirty()
			save_dict()
			return "learned"
		return "prompt"
	return ""


## The user overrode one of our corrections (retyped the original).
## Remember: never make that specific correction again.
func note_correction_overridden(typed: String, correction: String) -> void:
	var t := _clean(typed)
	var c := _clean(correction)
	if t != "" and c != "" and t != c:
		_correction_blacklist[t + "|" + c] = true
		# The user's version gets a trust boost — they insisted on it.
		_word_freq[t] = int(_word_freq.get(t, 0)) + 2
		save_dict()


func is_correction_blocked(typed: String, correction: String) -> bool:
	return _correction_blacklist.has(_clean(typed) + "|" + _clean(correction))


## Never-correct list for the settings UI: Array of [typed, correction].
func correction_blocks() -> Array:
	var out: Array = []
	for k in _correction_blacklist.keys():
		var parts := String(k).split("|", true, 1)
		if parts.size() == 2:
			out.append([parts[0], parts[1]])
	out.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	return out


func remove_correction_block(typed: String, correction: String) -> bool:
	var k := _clean(typed) + "|" + _clean(correction)
	if _correction_blacklist.has(k):
		_correction_blacklist.erase(k)
		save_dict()
		return true
	return false


func clear_correction_blocks() -> void:
	_correction_blacklist.clear()
	save_dict()


func _trim_word_freq() -> void:
	# Drop the least-used half. Base/learned words keep their dict entries;
	# this only trims the frequency table used for ranking.
	var keys: Array = _word_freq.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(_word_freq[a]) < int(_word_freq[b]))
	var drop := keys.size() / 2
	for i in drop:
		_word_freq.erase(keys[i])


func _trim_bigrams() -> void:
	var keys: Array = _bigrams.keys()
	keys.sort_custom(func(a: String, b: String) -> bool:
		return int(_bigrams[a]) < int(_bigrams[b])
	)
	var drop := keys.size() / 2
	for i in drop:
		_bigrams.erase(keys[i])


# --- suggestions ---------------------------------------------------------------
## Context-aware suggestions for a partial word. `prev_word` is the word
## before the cursor ("" if none). Learned + high-frequency words rank
## first; bigram followers of prev_word get a big boost; slang affinity
## boosts informal words when the user types informal.

## Marks the suggestion candidate cache dirty (vocabulary changed).
func _mark_candidates_dirty() -> void:
	_cand_dirty = true


## Rebuilds the cached candidate pool + first-char index if dirty.
## Learned words come first so they keep their ranking priority.
func _ensure_candidates() -> void:
	if not _cand_dirty:
		return
	_cand_dirty = false
	_cand_pool.clear()
	_cand_by_first.clear()
	var seen := {}
	for src in [_learned, _base_words]:
		for wcand in (src as Dictionary).keys():
			var c := String(wcand)
			if seen.has(c):
				continue
			seen[c] = true
			_cand_pool.append(c)
			var f := c.left(1)
			if not _cand_by_first.has(f):
				_cand_by_first[f] = []
			(_cand_by_first[f] as Array).append(c)


func suggestions(partial: String, prev_word: String = "", limit: int = 3) -> Array:
	var p := _clean(partial)
	if p == "":
		return []
	var prev := _clean(prev_word)
	_ensure_candidates()
	var scored: Array = []  # [word, score]
	var seen := {}
	# Prefix matches: only candidates sharing the first character can match.
	# This is the hot path — O(bucket) instead of O(3000).
	var bucket: Array = _cand_by_first.get(p.left(1), [])
	for wcand in bucket:
		var c := String(wcand)
		if c == p or seen.has(c):
			continue
		seen[c] = true
		if not c.begins_with(p):
			continue
		scored.append([c, _suggestion_score(c, p, prev, 100.0, true)])
	# Substring (non-prefix) matches: the full-pool scan is the keystroke
	# hot-spot (~7ms at 10k words). Only run it when the prefix pass came
	# up short — prefix completions are what typing needs; substring is a
	# fallback for "I can't remember how it starts". The pool is
	# frequency-ordered (common first), so capping the scan keeps the
	# useful matches while bounding the worst case.
	if p.length() >= 3 and scored.size() < limit:
		var scanned := 0
		for wcand in _cand_pool:
			if scanned >= 4000:
				break
			scanned += 1
			var c := String(wcand)
			if c == p or seen.has(c):
				continue
			seen[c] = true
			if p in c:
				scored.append([c, _suggestion_score(c, p, prev, 30.0, false)])
				# Enough for the bar — no need to score further.
				if scored.size() >= limit * 4:
					break
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var out: Array = []
	for i in mini(limit, scored.size()):
		out.append(String(scored[i][0]))
	return out


## Suggestion ranking (unchanged semantics — extracted so suggestions()
## can share it between the prefix fast path and the substring pass).
func _suggestion_score(c: String, p: String, prev: String, base: float, is_prefix: bool) -> float:
	var score := base
	# Personal vocabulary first.
	if _learned.has(c):
		score += 60.0
	# Frequency trust: words the user actually types rank higher.
	var freq := int(_word_freq.get(c, 0))
	score += minf(float(freq) * 4.0, 40.0)
	# Bigram context: what usually follows prev_word?
	if prev != "":
		var bcount := int(_bigrams.get(prev + "|" + c, 0))
		score += minf(float(bcount) * 15.0, 75.0)
	# Style: slang affinity boosts slang; low affinity slightly
	# prefers standard words.
	if c in SLANG_MARKERS:
		score += _slang_affinity * 50.0
	# Frequency prior: with a ~10k-word pool, common words must outrank
	# rare ones ("hel" -> hello/help/hell, not held/helm).
	var brank := int(_base_rank.get(c, 99999))
	if brank < 100:
		score += 30.0
	elif brank < 1000:
		score += 15.0
	# Shorter completions for a prefix are usually what you want.
	if is_prefix:
		score -= float(c.length() - p.length()) * 1.5
	return score


# --- autocorrect -----------------------------------------------------------------
## Context-aware correction. `prev_word` is the word before the one being
## corrected. Returns the corrected word, or "" for no correction.
##
## Ranking: edit distance (QWERTY-aware) + bigram fit + personal frequency.
## A candidate must beat the typed word's own score — frequent user words
## are never "corrected" away.

## Fast autocorrect candidate pool: words sharing the typed word's first
## character, plus words whose first character is QWERTY-adjacent (a
## fat-fingered start). Shrinks the per-space/send edit-distance scan from
## ~10k to a few hundred. Learned words are included (via _ensure_candidates).
func _fast_autocorrect_pool(w: String) -> Array:
	_ensure_candidates()
	var first := w.left(1)
	var seen := {}
	var out: Array = []
	var add_bucket := func(f: String) -> void:
		for c in _cand_by_first.get(f, []):
			var s := String(c)
			if not seen.has(s):
				seen[s] = true
				out.append(s)
	add_bucket.call(first)
	for row in QWERTY_ROWS:
		var rs := row as String
		var i: int = rs.find(first)
		if i >= 0:
			if i > 0:
				add_bucket.call(rs.substr(i - 1, 1))
			if i < rs.length() - 1:
				add_bucket.call(rs.substr(i + 1, 1))
			break
	return out


func autocorrect(word: String, prev_word: String = "") -> String:
	var w := _clean(word)
	if w == "" or is_known(w):
		return ""
	if aggression == "low":
		return ""  # suggestions only, never auto-replace
	# The user overrode a correction for this exact word: they type it
	# deliberately, so leave it alone entirely (not "corrected" to some
	# other word either). Jeremy 2026-10-06 contract.
	var tkey := w + "|"
	for k in _correction_blacklist.keys():
		if String(k).begins_with(tkey):
			return ""
	var prev := _clean(prev_word)
	# If the user types this "typo" regularly, it's their word — trust it.
	var typed_freq := int(_word_freq.get(w, 0))
	var max_d := 1.0 if aggression == "medium" else 2.0
	# Fast path: scan candidates sharing the first character (plus
	# QWERTY-neighbor first characters, for fat-fingered starts) instead of
	# the whole ~10k pool. Falls back to a full scan when nothing is close —
	# covers dropped/wrong first letters; the character-overlap prefilter
	# keeps that rare pass cheap (garbage input shares nothing with the
	# pool, so almost no edit distances run).
	var res: Array = _scan_autocorrect(_fast_autocorrect_pool(w), w, prev, max_d, {}, 0)
	if String(res[0]) == "":
		var typed_chars := {}
		for i in w.length():
			typed_chars[w[i]] = true
		var need := 2 if w.length() > 3 else 1
		res = _scan_autocorrect(_base_words.keys() + _learned.keys(), w, prev, max_d, typed_chars, need)
	var best := String(res[0])
	var best_score := float(res[1])
	var best_dist := float(res[2])
	if best == "":
		return ""
	match aggression:
		"medium":
			# Obvious single-char typos only — and not words the user
			# has adopted (typed 3+ times).
			if best_dist <= 1.0 and typed_freq < 3:
				return best
			return ""
		"high":
			# Aggressive: the correction must be a clearly better fit.
			if best_score > 0.0:
				return best
			return ""
		"aggressive":
			# Rewrite with confidence; still respects the blacklist and
			# never touches words the user types more than the candidate.
			if best_score >= 0.0 and typed_freq <= int(_word_freq.get(best, 0)) + 1:
				return best
			return ""
	return ""


## Scans one candidate pool for the best correction. Returns
## [best_word, best_score, best_dist]. When need_overlap > 0 (the rare
## full-pool fallback), candidates sharing fewer than need_overlap unique
## characters with the typed word skip the edit distance — a real typo at
## distance <= 2 always shares nearly all its letters, garbage shares none.
func _scan_autocorrect(scan: Array, w: String, prev: String, max_d: float,
		typed_chars: Dictionary, need_overlap: int) -> Array:
	var best := ""
	var best_score := -9999.0
	var best_dist := 99.0
	# Empty blacklist: skip the per-candidate _clean + lookup entirely.
	var check_blocked := not _correction_blacklist.is_empty()
	for wcand in scan:
		var c := String(wcand)
		# Length difference alone lower-bounds the edit distance
		# (insert/delete cost 1.0 each), so past max_d it can never match.
		if absf(float(c.length() - w.length())) > max_d:
			continue
		if check_blocked and is_correction_blocked(w, c):
			continue
		if need_overlap > 0 and not _char_overlap_ok(c, typed_chars, need_overlap):
			continue
		var d := _edit_distance(w, c, max_d)
		if d > max_d:
			continue
		var s := _candidate_score(c, w, prev, d)
		if s > best_score:
			best_score = s
			best = c
			best_dist = d
	return [best, best_score, best_dist]


## True when candidate shares at least `need` unique characters with the
## typed word (whose unique chars are in typed_chars).
func _char_overlap_ok(c: String, typed_chars: Dictionary, need: int) -> bool:
	var overlap := 0
	var seen := {}
	for i in c.length():
		var ch := c[i]
		if seen.has(ch):
			continue
		seen[ch] = true
		if typed_chars.has(ch):
			overlap += 1
			if overlap >= need:
				return true
	return false


## Candidate score: positive means "better than leaving it alone".
## Base/learned words get a real-word bonus; personal frequency and
## bigram context add more; edit distance subtracts.
func _candidate_score(cand: String, typed: String, prev: String, dist: float) -> float:
	var score := 0.0
	# It's a real word — that alone is worth a lot vs. a typo.
	if _learned.has(cand):
		score += 50.0
	elif _base_words.has(cand):
		score += 35.0
	# Frequency prior: common words win ties, so "teh" corrects to "the"
	# (rank 0) rather than "ten"/"tea". Curated words are common by
	# construction (ranks 0-808).
	var brank := int(_base_rank.get(cand, 99999))
	if brank < 100:
		score += 30.0
	elif brank < 1000:
		score += 15.0
	# The user types the candidate a lot: strong signal.
	var cfreq := int(_word_freq.get(cand, 0))
	score += minf(float(cfreq) * 8.0, 80.0)
	# The user types the "typo" a lot: trust it instead (negative).
	var tfreq := int(_word_freq.get(typed, 0))
	score -= minf(float(tfreq) * 10.0, 60.0)
	# Bigram context fit.
	if prev != "":
		var bcount := int(_bigrams.get(prev + "|" + cand, 0))
		score += minf(float(bcount) * 20.0, 100.0)
	# Slang style: don't "correct" toward formal when the user is informal.
	if cand in SLANG_MARKERS:
		score += _slang_affinity * 30.0
	# Prefix relationship: "helo" is likely an unfinished "hello".
	if cand.begins_with(typed) or typed.begins_with(cand):
		score += 15.0
	# Dropped-a-letter: single insertion ("helo"->"hello") is a very
	# common fast-typing pattern — prefer it over substitutions.
	if cand.length() == typed.length() + 1 and dist <= 1.0:
		score += 12.0
	# Edit distance penalty (QWERTY-aware distance already applied).
	score -= float(dist) * 20.0
	return score


## QWERTY-aware Levenshtein: adjacent-key substitutions and adjacent
## transpositions cost less — they look like real finger slips.
## Returns a float: insert/delete = 1.0, substitute = 1.0 (0.6 if the keys
## are adjacent on QWERTY), transposition = 1.0.
##
## max_d: callers only care whether the distance is within max_d, so the DP
## bails as soon as every value in a row exceeds max_d — the final distance
## can only grow from there (each next-row cell is built from current-row
## values plus a non-negative cost). Returns max_d + 1.0 in that case;
## distances within the bound are computed exactly as before.
func _edit_distance(a: String, b: String, max_d: float = 99.0) -> float:
	var m := a.length()
	var n := b.length()
	if m == 0:
		return float(n)
	if n == 0:
		return float(m)
	# Length difference alone lower-bounds the distance (insert/delete 1.0).
	if absf(float(m - n)) > max_d:
		return max_d + 1.0
	# Transposition shortcut: "teh" vs "the".
	if m == n and m >= 2:
		var diffs: Array = []
		for i in m:
			if a[i] != b[i]:
				diffs.append(i)
		if diffs.size() == 2 and int(diffs[1]) == int(diffs[0]) + 1 \
				and a[int(diffs[0])] == b[int(diffs[1])] \
				and a[int(diffs[1])] == b[int(diffs[0])]:
			return 1.0
	var prev: Array = []
	var cur: Array = []
	for j in range(n + 1):
		prev.append(float(j))
	for i in range(1, m + 1):
		cur.clear()
		cur.append(float(i))
		var row_min := float(i)
		for j in range(1, n + 1):
			var sub_cost := 0.0
			if a[i - 1] != b[j - 1]:
				sub_cost = 0.85 if _qwerty_adjacent(a[i - 1], b[j - 1]) else 1.0
			var v := minf(minf(prev[j] + 1.0, cur[j - 1] + 1.0), prev[j - 1] + sub_cost)
			cur.append(v)
			if v < row_min:
				row_min = v
		if row_min > max_d:
			return max_d + 1.0
		prev = cur.duplicate()
	return prev[n]


func _qwerty_adjacent(a: String, b: String) -> bool:
	if a == b:
		return true
	for row in QWERTY_ROWS:
		var ia: int = (row as String).find(a)
		var ib: int = (row as String).find(b)
		if ia >= 0 and ib >= 0 and absf(float(ia - ib)) == 1.0:
			return true
	return false


# --- word learning API -------------------------------------------------------------

func word_completed(word: String) -> String:
	# Legacy entry point: route through the full learning pipeline.
	return note_word_typed(word)


func add_learned_word(word: String) -> void:
	var w := _clean(word)
	if w != "" and not is_known(w):
		_learned[w] = true
		_word_freq[w] = int(_word_freq.get(w, 0)) + 1
		_mark_candidates_dirty()
		save_dict()


func remove_learned_word(word: String) -> bool:
	var w := _clean(word)
	if _learned.has(w):
		_learned.erase(w)
		_mark_candidates_dirty()
		save_dict()
		return true
	return false


# --- persistence ---------------------------------------------------------------------

func save_dict() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("keyboard", "aggression", aggression)
	cfg.set_value("keyboard", "auto_learn", auto_learn)
	cfg.set_value("keyboard", "kb_theme", kb_theme)
	cfg.set_value("keyboard", "auto_space", auto_space)
	cfg.set_value("keyboard", "learned", _learned.keys())
	cfg.set_value("keyboard", "slang_affinity", _slang_affinity)
	cfg.set_value("model", "word_freq", _word_freq)
	cfg.set_value("model", "bigrams", _bigrams)
	cfg.set_value("model", "correction_blacklist", _correction_blacklist.keys())
	cfg.save(_save_path())


func load_dict() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_save_path()) != OK:
		return
	var agg := String(cfg.get_value("keyboard", "aggression", "medium"))
	if agg in AGGRESSION_LEVELS:
		aggression = agg
	auto_learn = bool(cfg.get_value("keyboard", "auto_learn", false))
	kb_theme = String(cfg.get_value("keyboard", "kb_theme", "dark"))
	auto_space = bool(cfg.get_value("keyboard", "auto_space", true))
	_slang_affinity = clampf(float(cfg.get_value("keyboard", "slang_affinity", 0.0)), 0.0, 1.0)
	_learned.clear()
	for w in cfg.get_value("keyboard", "learned", []):
		_learned[_clean(String(w))] = true
	_mark_candidates_dirty()
	_word_freq.clear()
	var wf: Dictionary = cfg.get_value("model", "word_freq", {})
	for k in wf.keys():
		_word_freq[_clean(String(k))] = int(wf[k])
	_bigrams.clear()
	var bg: Dictionary = cfg.get_value("model", "bigrams", {})
	for k in bg.keys():
		_bigrams[String(k)] = int(bg[k])
	_correction_blacklist.clear()
	for k in cfg.get_value("model", "correction_blacklist", []):
		_correction_blacklist[String(k)] = true


func reset_learned() -> void:
	_learned.clear()
	_unknown_counts.clear()
	last_prompt_word = ""
	save_dict()


func reset_model() -> void:
	# Full personal-model reset (keeps settings + learned words).
	_word_freq.clear()
	_bigrams.clear()
	_correction_blacklist.clear()
	_slang_affinity = 0.0
	_last_word = ""
	save_dict()
