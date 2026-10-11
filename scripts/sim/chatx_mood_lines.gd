## Cursing Gnomes — chatx mood line data (Jeremy's NPC emotion simulation).
##
## Verbatim port of HTML fix79's CHATX_MOOD_LINES (22 moods x 4 factions x
## 4 lines = 352 faction-voiced lines) and CHATX_MOOD_ASIDES (22 moods x
## 2 asides). The HTML's cheeseManiaInject() is applied at conversion
## time: human pools gain the per-mood cheese lines, and gnome/ogre/elf
## joyful/excited/content pools gain the faction food-pride lines
## (Jeremy's 2026-09-28 CHEESE MANIA request — humans are comically
## obsessed with cheese; gnomes love tacos, ogres turkey, elves honeycake).
##
## CHEESE_LINES / CHEESE_SCREAMS feed the ambient chatter hook
## (SimDialogue "chatter": humans near a restaurant scream about cheese).
##
## Pure data — no logic. Consumed by SimChatxMood.pick_line() /
## SimChatxMood.flavor(). All lines are plain ASCII (iPhone tofu rule:
## no emoji or glyphs in chat text).
class_name ChatxMoodLines
extends RefCounted


const LINES := {
	"joyful": {
		"gnome": [
			"I could kiss the whole kingdom! Don't tempt me, I'll do it.",
			"Today the gold is shinier and the ale tastes like victory!",
			"Ha! I woke up grinning and I haven't stopped. Send help. Or ale.",
			"Everything's wonderful and I take full credit. You're welcome.",
			"Tacos beat everything. Gnome science proved it.",
			"A taco a day keeps the doom away."
		],
		"human": [
			"I feel magnificent today. The whole court can see it. I've been told.",
			"Joy! Actual, honest joy. I've scheduled more of it for tomorrow.",
			"The sun is shining, the ledgers balance, and I am thriving.",
			"I've been humming since dawn. The guards are concerned. I'm not.",
			"CHEESE! I just... CHEESE!!",
			"This is the happiest I've been since the great gouda of last spring!"
		],
		"elf": [
			"Darling, I am simply RADIANT today. Bask accordingly.",
			"The grove sings and I sing with it. Off-key, but with feeling.",
			"Joy looks good on me, doesn't it? It looks good on everyone, but especially me.",
			"I woke up luminous. It's a whole thing. You'll get used to it.",
			"Honeycake, darling. The only civilized dessert.",
			"One simply does not refuse honeycake."
		],
		"ogre": [
			"ME SO HAPPY! ME DANCE! ME ALREADY DANCING! LOOK!",
			"BEST DAY! ME SMILE SO BIG ME FACE HURT! WORTH IT!",
			"ME HAPPY! YOU HAPPY! EVERYONE HAPPY! HAPPY MANDATORY!",
			"ME WANT HUG WHOLE WORLD! WORLD TOO BIG! ME HUG YOU INSTEAD!",
			"TURKEY! BIG BIRD! ME EAT WHOLE!",
			"Me once ate a whole turkey. Me would do it again. Me WILL."
		]
	},
	"content": {
		"gnome": [
			"Ah. Good ale, warm hearth, full purse. Life's alright.",
			"Can't complain. Well, I can. I won't. Today.",
			"Things are steady. Steady pays the bills. Mostly.",
			"Nice day. Quiet. Nobody owes me money. A miracle.",
			"Tacos beat everything. Gnome science proved it.",
			"A taco a day keeps the doom away."
		],
		"human": [
			"All is well. The kingdom hums along, and so do I.",
			"A quiet, competent day. My favorite kind.",
			"I'm at peace with the ledgers today. A rare and precious thing.",
			"Everything in its place. Even me.",
			"Life's good. Cheese is better.",
			"A quiet day, a full wheel, no complaints."
		],
		"elf": [
			"The grove is calm, and so am I. A matching set.",
			"Contentment suits me, darling. Like everything else.",
			"All is as it should be. The flowers agree. They told me.",
			"A gentle day. I might even be pleasant to mortals. Don't quote me.",
			"Honeycake, darling. The only civilized dessert.",
			"One simply does not refuse honeycake."
		],
		"ogre": [
			"ME GOOD. BELLY FULL. HEART FULL. ALL GOOD.",
			"ME SIT. ME REST. ME HAPPY QUIET.",
			"DAY NICE. ME NICE. EVERYTHING NICE.",
			"ME CONTENT. THAT MEANS FULL AND SLEEPY. ME LIKE.",
			"TURKEY! BIG BIRD! ME EAT WHOLE!",
			"Me once ate a whole turkey. Me would do it again. Me WILL."
		]
	},
	"proud": {
		"gnome": [
			"Did you SEE what I did? No? Let me tell you. In detail.",
			"I'm not saying I'm the best. I'm saying the trophies say it.",
			"Go on, admire me. I'll wait. Take your time.",
			"I did that. Me. With these hands. Magnificent hands."
		],
		"human": [
			"I've earned this moment. The record will show it.",
			"A job well done. I shall allow myself a small, dignified smile.",
			"The court noticed. They always notice. I make sure of it.",
			"Excellence is a habit. I am habitual.",
			"I aged that cheddar MYSELF. Bow before it.",
			"My cheese board has won awards. Unverified awards."
		],
		"elf": [
			"Naturally I succeeded. I always do. It's practically a burden.",
			"Darling, did you witness my triumph? Everyone did. I made sure.",
			"Perfection, as usual. The grove applauds. Listen. ...There.",
			"I don't mean to gloat. I mean to accurately report my greatness."
		],
		"ogre": [
			"ME DID IT! ME STRONG! ME SMART! ME BEST!",
			"LOOK WHAT ME DO! ME PROUD! ME FLEX!",
			"ME WIN! ME CHAMPION! ME GET BIGGEST PIECE!",
			"ME ACCOMPLISH! THAT BIG WORD! ME LEARNED IT!"
		]
	},
	"excited": {
		"gnome": [
			"Did you hear?! Something's happening! I don't know what! Exciting!",
			"Oh, oh! Big news! ...I forgot the news. But it's BIG!",
			"I can barely sit still! Somebody give me something to do!",
			"Something wonderful is about to happen. I can feel it in my beard.",
			"Tacos beat everything. Gnome science proved it.",
			"A taco a day keeps the doom away."
		],
		"human": [
			"Extraordinary developments! I can hardly contain myself.",
			"The reports are in and they're THRILLING. Well, thrilling for reports.",
			"I've had three cups of coffee. I regret nothing. Everything is possible.",
			"Do you feel that? That electric possibility? Neither do I, but pretend.",
			"THE CHEESE SHOP RESTOCKED! I REPEAT, RESTOCKED!",
			"New cheese day! NEW CHEESE DAY!"
		],
		"elf": [
			"Darling! News! Gossip! Events! I am simply aquiver.",
			"Something delicious is unfolding. I can smell it on the wind.",
			"Oh, I do love a development. Tell me everything. Twice.",
			"My leaves are tingling. That's how you know it's serious.",
			"Honeycake, darling. The only civilized dessert.",
			"One simply does not refuse honeycake."
		],
		"ogre": [
			"OH OH OH! SOMETHING HAPPENING! ME EXCITED!",
			"ME BOUNCING! ME CAN'T STOP! BOING BOING!",
			"WHAT WHAT WHAT?! TELL ME! ME LOVE NEWS!",
			"ME HEART RACING! ME LEGS RUNNING! ME ALREADY THERE!",
			"TURKEY! BIG BIRD! ME EAT WHOLE!",
			"Me once ate a whole turkey. Me would do it again. Me WILL."
		]
	},
	"grateful": {
		"gnome": [
			"Thank you. Really. I don't say it often. Don't get used to it.",
			"You've done me a kindness and I won't forget it. I keep lists.",
			"I'm grateful. There. I said it. The words taste weird.",
			"Much obliged, friend. The gnomes remember. We write it down."
		],
		"human": [
			"I am deeply grateful. You've my sincere thanks.",
			"Your kindness hasn't gone unnoticed. Far from it.",
			"I owe you a debt of gratitude. I pay my debts. Usually.",
			"Thank you, {name}. From the bottom of this bureaucratic heart.",
			"Bless whoever invented cheese. Saint of dairy.",
			"Thank you for the cheese. I'd die for you now."
		],
		"elf": [
			"Oh, darling. I'm genuinely touched. Don't tell the others.",
			"Gratitude! How novel. How... warm. Thank you, sweetling.",
			"You've given me something precious. I shall treasure it. Briefly. Then show everyone.",
			"The grove itself thanks you. It rustles appreciatively."
		],
		"ogre": [
			"THANK YOU! ME GRATEFUL BIG! ME REMEMBER FOREVER!",
			"YOU KIND! ME HEART WARM! ME MAKE YOU SOUP!",
			"ME OWE YOU! ME PAY BACK HUNDRED TIMES!",
			"GRATEFUL! THAT FEELING IN CHEST! ME LIKE IT!"
		]
	},
	"amused": {
		"gnome": [
			"Heh. That's funny. Don't let it go to your head.",
			"Oh, that's rich. Tell it again. Slower. I want to savor it.",
			"Ha! Okay, you've got a funny bone. I'll allow it.",
			"Amusing. For a non-gnome. High praise, that."
		],
		"human": [
			"Ha! Well played. I needed that laugh.",
			"Amusing indeed. The court could use more wit like yours.",
			"You've a sharp tongue, {name}. I mean that kindly. Mostly.",
			"I laughed. Out loud. The guards heard. Worth it.",
			"Heh. The cheese has holes. Like my plans.",
			"Someone said 'cut the cheese' and I laughed for an hour."
		],
		"elf": [
			"Oh! Delightful. Do go on, darling. I'm thoroughly entertained.",
			"How droll. How positively delicious. More, please.",
			"You amuse me, sweetling. Few manage it. Fewer survive it.",
			"A laugh! From ME! You should be honored. I am. Slightly."
		],
		"ogre": [
			"HAHA! FUNNY! ME LIKE FUNNY!",
			"YOU MAKE ME LAUGH! ME LAUGH BIG!",
			"HEE HEE! ME GIGGLING! ME TRY STOP! CAN'T!",
			"FUNNY WORDS! ME REPEAT THEM! ME FUNNY NOW TOO!"
		]
	},
	"sad": {
		"gnome": [
			"Eh. Grey day. The ale tastes like... ale. But sadder.",
			"Don't mind me. Just having a think. A gloomy one.",
			"Some days the gold doesn't shine. Today's one of them.",
			"I'd tell you what's wrong, but I'd rather just sit here being glum."
		],
		"human": [
			"Forgive me. I'm a little low today. It'll pass.",
			"Some days weigh heavier than others. Today's heavy.",
			"I appreciate your patience. I'm not quite myself.",
			"The ledgers are fine. It's just... me. I'll manage.",
			"Even cheese can't fix this. ...Bring cheese anyway.",
			"I'm sad. Cheese understands."
		],
		"elf": [
			"The grove weeps a little today, darling. So do I.",
			"Even eternal things have grey days. This is mine.",
			"Oh, sweetling. Hold my hand? Just for a moment.",
			"My petals droop today. Don't stare."
		],
		"ogre": [
			"ME SAD. ME DON'T KNOW WHY. ME JUST SAD.",
			"ME HEART HEAVY. LIKE EATING ROCKS. SAD ROCKS.",
			"ME WANT CHEER UP. ME DON'T KNOW HOW.",
			"IT GREY DAY INSIDE ME. ME SORRY."
		]
	},
	"lonely": {
		"gnome": [
			"Quiet in here. Too quiet. Even my echo left.",
			"Nobody to share the ale with. Ale's sadder alone.",
			"I miss... people. Don't tell anyone I said that.",
			"Ever feel like the whole world's at a party you weren't invited to?"
		],
		"human": [
			"The court's full of people and I've never felt more alone.",
			"Company, {name}. That's all I ask. Just... company.",
			"It's lonely at the top. It's lonely everywhere, honestly.",
			"I'd give a week's taxes for a real conversation.",
			"It's just me and the cheese rind tonight.",
			"Cheese never leaves. Cheese stays."
		],
		"elf": [
			"The grove is vast and I am small within it today, darling.",
			"Surrounded by beauty, starved for company. The irony.",
			"Oh, sweetling. Stay a while? The silence is loud today.",
			"Even the trees feel far away. Come closer."
		],
		"ogre": [
			"ME LONELY. ME WANT FRIEND. ARE YOU FRIEND?",
			"NOBODY TO PLAY WITH. ME PLAY ALONE. NOT FUN.",
			"ME BIG. ME STRONG. ME STILL NEED HUG.",
			"EMPTY FEELING. ME FILL WITH SNACKS. STILL EMPTY."
		]
	},
	"grieving": {
		"gnome": [
			"Lost someone. Don't... don't try to fix it. Just sit a while.",
			"The world's got a gnome-shaped hole in it now.",
			"I keep reaching for the second mug. Old habits.",
			"Grief's a heavy ledger. The columns never balance."
		],
		"human": [
			"We've suffered a loss. The flags fly low. So do I.",
			"I've written the condolences. The words felt so small.",
			"Please excuse me. Some wounds need quiet.",
			"They're gone, and the kingdom feels colder for it.",
			"They loved cheese. We share that now.",
			"Pour one out. Then eat cheese in their honor."
		],
		"elf": [
			"The grove mourns, darling. The leaves fall out of season.",
			"We do not die easily, which makes it worse when we do.",
			"Light a candle. Say their name. Remember.",
			"My heart is winter. Spring will come. Not today."
		],
		"ogre": [
			"ME LOST SOMEONE. ME HEART BROKEN BIG.",
			"ME CRY. ME NOT ASHAMED. ME LOVED THEM.",
			"THEY GONE. ME STILL HERE. ME DON'T LIKE IT.",
			"ME REMEMBER THEM. ME TELL STORIES. THEY LIVE IN STORIES."
		]
	},
	"angry": {
		"gnome": [
			"I'm FURIOUS. Everything's stupid. Especially you. No offense. Offense.",
			"Somebody's going to pay. Preferably in gold. Painfully.",
			"My beard is bristling. That's how you know it's serious.",
			"Cross me today and you'll meet the business end of my temper."
		],
		"human": [
			"I am... displeased. Profoundly. Officially.",
			"My patience has left the building. It took the guards with it.",
			"Someone will answer for this. In triplicate.",
			"I've never been so angry. The inkwell knows. It's shattered.",
			"I'M NOT ANGRY, I'M JUST PASSIONATE ABOUT CHEESE!",
			"Touch my cheese and lose the hand. Them's the rules."
		],
		"elf": [
			"Darling, I am LIVID. The grove itself trembles.",
			"My fury is a beautiful, terrible thing. Behold it. Briefly.",
			"I've cursed three people today. In verse. It helped.",
			"Do NOT test me today, sweetling. The thorns are out."
		],
		"ogre": [
			"ME MAD! ME SMASH! ME SMASH SMALL THINGS FIRST!",
			"GRRR! ME ANGRY! ME SEE RED! ME SEE YOU! RUN!",
			"ME FURIOUS! ME PUNCH TREE! TREE SORRY NOW!",
			"STAY BACK! ME VOLCANO! ME ERUPT!"
		]
	},
	"bitter": {
		"gnome": [
			"Oh, sure. Trust people. That always works out. Bitter? Me? Never.",
			"Life's taught me plenty. Mostly that life's a cheat.",
			"I used to believe in things. Then I met people.",
			"Sweet? I was sweet once. Then the world happened."
		],
		"human": [
			"Experience has made me... realistic. Call it realism.",
			"I've seen how the game is played. I no longer enjoy playing.",
			"Optimism is a young courtier's luxury. I've spent mine.",
			"Forgive the edge in my voice. It's earned.",
			"The world's gone sour. Unlike a fine aged cheddar.",
			"Trust no one. Except cheese. Cheese never lied."
		],
		"elf": [
			"Darling, I've lived centuries. Disappointment compounds.",
			"The grove remembers every slight. So do I. Vividly.",
			"Bitter? No. Seasoned. Like a fine, furious wine.",
			"I trusted once. The scars are lovely. Want to see?"
		],
		"ogre": [
			"ME TRUSTED. ME HURT. ME LEARN. ME NOT TRUST EASY NOW.",
			"WORLD MEAN SOMETIMES. ME REMEMBER. ME NOT FORGET.",
			"ME SMILE LESS NOW. ME MISS SMILING.",
			"BITTER TASTE. LIKE BAD BERRY. ME SPIT IT. IT STAY."
		]
	},
	"jealous": {
		"gnome": [
			"Oh, THEY get the good stall? Must be nice. Must be REAL nice.",
			"I'm not jealous. I'm just... aggressively observant of others' luck.",
			"Sure, give THEM the praise. I'll be over here. Seething. Quietly.",
			"Must be wonderful, being the favorite. I'd hate it. Probably."
		],
		"human": [
			"I couldn't help but notice the attention THEY received.",
			"Envy is unbecoming. I am becoming it anyway.",
			"The court favors whom it favors. I've made a list.",
			"I'm happy for them. I'm also keeping score.",
			"THEY got the last wheel?! MUST BE NICE.",
			"Oh, YOUR cheese is better? We'll see about that."
		],
		"elf": [
			"Oh, how LOVELY for them. Truly. Deeply. Through gritted teeth.",
			"Darling, I'm not jealous. I'm just better and underappreciated.",
			"They got WHAT? ...I mean, how nice. How utterly nice.",
			"Envy doesn't suit me. Nothing ill-suited has ever stopped me."
		],
		"ogre": [
			"THEY GOT BIGGER PIECE! ME SAW! ME COUNTED!",
			"ME JEALOUS! ME WANT WHAT THEY HAVE! ME WANT BIGGER!",
			"WHY THEM NOT ME?! ME GOOD TOO! ME GOOD ENOUGH!",
			"ME GREEN WITH JEALOUS! ME ALREADY GREEN! ME DOUBLE GREEN!"
		]
	},
	"afraid": {
		"gnome": [
			"Something's wrong. I can feel it in my fillings.",
			"I don't scare easy. I'm scared easy right now. Don't judge.",
			"Keep your voice down. The walls have ears. Probably.",
			"I've hidden the gold. I've hidden myself. Priorities."
		],
		"human": [
			"I won't lie to you, {name}. I'm frightened.",
			"The reports are... concerning. I've doubled the guard.",
			"Stay close. Please. That's an order. A scared order.",
			"I've faced down armies. This feels worse.",
			"Hold me. And bring cheese. Cheese first.",
			"Something's wrong. I can feel it in my cheese."
		],
		"elf": [
			"Darling, something stirs in the dark. Even I feel it.",
			"The grove is afraid. When the grove is afraid, I am terrified.",
			"Hold me, sweetling? Just... for a moment. Don't tell.",
			"My magic feels thin today. Like ice. Don't step hard."
		],
		"ogre": [
			"ME SCARED. ME BIG BUT ME SCARED. DON'T LAUGH.",
			"SOMETHING BAD COMING. ME FEEL IT IN BONES.",
			"ME WANT HIDE. ME TOO BIG TO HIDE. ME HIDE ANYWAY.",
			"ME BRAVE USUALLY. TODAY ME NOT BRAVE. TODAY ME SMALL."
		]
	},
	"anxious": {
		"gnome": [
			"Can't sit still. Too many what-ifs. What if the what-ifs have what-ifs?",
			"My stomach's doing acrobatics. Unpaid acrobatics.",
			"Something's coming. Good or bad, I don't know. The not-knowing's the worst.",
			"I've counted the gold three times. It's all there. Probably."
		],
		"human": [
			"The uncertainty is... difficult. I've reviewed every scenario.",
			"I haven't slept. The what-ifs keep holding council in my head.",
			"So much hangs in the balance. I can feel the scales trembling.",
			"Breathe. That's what they say. I'm trying. It's not working.",
			"My nerves are shot. Cheese. Cheese will steady me.",
			"Can't settle. Unless there's brie. Is there brie?"
		],
		"elf": [
			"My petals won't stop trembling, darling. Most unbecoming.",
			"The future is a fog and I've lost my way in it.",
			"I've read the omens six times. They contradict each other. Rude.",
			"Anxiety, sweetling, is just excitement without the fun parts."
		],
		"ogre": [
			"ME WORRIED. ME PACING. ME WORE HOLE IN FLOOR.",
			"WHAT IF BAD THING?! ME THINK ABOUT IT! ME CAN'T STOP!",
			"ME STOMACH JUMPY. LIKE FROGS. ME DON'T LIKE FROGS IN STOMACH.",
			"ME NEED GOOD NEWS. OR SNACK. SNACK FIRST. THEN NEWS."
		]
	},
	"stressed": {
		"gnome": [
			"Too much! Too many ledgers! Too many people wanting things!",
			"I'm one gnome. ONE. I can't do everything. Watch me try. Ugh.",
			"My beard's going grey. From stress. It's distinguished. It's stress.",
			"If one more person asks me for something, I'm moving to a cave."
		],
		"human": [
			"The workload is... considerable. I've stopped counting the petitions.",
			"Every bell brings another crisis. The bells mock me now.",
			"I need a holiday. I've needed one for six years.",
			"Delegation. I must delegate. After I finish everything myself.",
			"Too much at once. I need cheese and silence.",
			"I'm at my limit. My cheese limit is higher, though."
		],
		"elf": [
			"Darling, I am SPREAD thin. Like cheap jam on too much toast.",
			"The grove demands, the court demands, my hair demands. Enough.",
			"I need a century-long nap. I'll settle for a weekend.",
			"Stress wrinkles, sweetling. Look. ...Don't look."
		],
		"ogre": [
			"TOO MUCH! ME HEAD FULL! ME NEED QUIET!",
			"EVERYONE WANT SOMETHING! ME HAVE ONLY TWO HANDS!",
			"ME STRESSED! ME EAT FEELINGS! ME OUT OF FEELINGS! NEED MORE FOOD!",
			"ME NEED NAP! BIG NAP! NOBODY WAKE ME!"
		]
	},
	"exhausted": {
		"gnome": [
			"I'm running on fumes and spite. Mostly spite.",
			"Sleep? I remember sleep. Fondly. Like an ex.",
			"If I sit down, I'm not getting up. You've been warned.",
			"My bones are tired. My beard is tired. Everything's tired."
		],
		"human": [
			"Forgive me. I'm running on empty. The candle's burned at both ends.",
			"I've given everything today. There's nothing left but politeness.",
			"Exhaustion is my constant companion. We've become close.",
			"I'd sleep for a week if the kingdom would allow it. It won't.",
			"Running on empty. And cheese fumes.",
			"Barely standing. The cheese is holding me up."
		],
		"elf": [
			"Darling, I am WEARY. Centuries of it, all landing today.",
			"Even my glow is dim. That's how tired I am.",
			"I need rest. Real rest. Not the decorative kind.",
			"Carry me, sweetling? ...I'm mostly joking. Mostly."
		],
		"ogre": [
			"ME TIRED. ME SO TIRED. ME SLEEP STANDING.",
			"ME EYES HEAVY. LIKE ROCKS. ME CLOSE THEM... ...ME AWAKE. BARELY.",
			"ME NEED SLEEP. BIG SLEEP. SLEEP LIKE BEAR. BEAR SMART.",
			"ME DONE. ME FINISHED. ME BECOME BLANKET NOW."
		]
	},
	"bored": {
		"gnome": [
			"Nothing's happening. NOTHING. I've alphabetized the pickles.",
			"I'm so bored I'm considering honest work. Desperate times.",
			"Entertain me, {name}. You're my only hope. No pressure.",
			"I've counted the ceiling beams. Twice. They haven't changed."
		],
		"human": [
			"The court's quiet. Too quiet. I've reorganized the seals.",
			"Boredom is the tax on peace. I'm paying heavily today.",
			"Nothing requires my attention. It's unsettling, honestly.",
			"I've read the same decree four times. For fun. There is no fun.",
			"Nothing ever happens. Except cheese. Cheese happens.",
			"Entertain me. With cheese. Please."
		],
		"elf": [
			"Darling, I am BORED. Eternally, cosmically bored.",
			"Nothing sparkles today. I've checked. Twice.",
			"Amuse me, sweetling, or I shall do something drastic. Like redecorate.",
			"I've lived centuries and today is somehow the longest day."
		],
		"ogre": [
			"ME BORED. ME BORED BIG. ME NEED SOMETHING!",
			"NOTHING TO DO! ME POKE WALL! WALL BORED TOO!",
			"ME WANT ADVENTURE! OR SNACK! ADVENTURE SNACK!",
			"ME COUNT FINGERS! TEN! ME COUNT AGAIN! STILL TEN!"
		]
	},
	"hopeful": {
		"gnome": [
			"Got a feeling about today. A good one. Don't jinx it.",
			"Things might turn around. I've got a plan. It's only slightly illegal.",
			"Hope's a dangerous thing. I'm dangerously hopeful.",
			"Maybe, just maybe, this all works out. Fingers crossed. Toes too."
		],
		"human": [
			"I dare to hope, {name}. The signs are... encouraging.",
			"Perhaps the tide is turning. I've read the reports twice to be sure.",
			"Hope is a strategy. An underrated one.",
			"For the first time in a while, I see light ahead.",
			"Fingers crossed. And cheese crossed.",
			"Good things coming. I can smell them. They smell like gouda."
		],
		"elf": [
			"Darling, I feel a green shoot of hope. Don't step on it.",
			"The omens whisper kindly today. I choose to listen.",
			"Hope blooms eternal, sweetling. Like me.",
			"Something good stirs. The grove feels it. So do I."
		],
		"ogre": [
			"ME HOPEFUL! ME THINK GOOD THINGS COMING!",
			"ME FEEL LUCKY! LIKE FINDING EXTRA PIE!",
			"MAYBE TODAY GREAT! ME BELIEVE! ME BELIEVE HARD!",
			"HOPE! ME HOLD IT TIGHT! ME NOT LET GO!"
		]
	},
	"guilty": {
		"gnome": [
			"I did a thing. A bad thing. Don't ask. ...It involved pie.",
			"My conscience is gnawing at me. Rude little thing.",
			"I owe someone an apology. Several someones. It's a list.",
			"I feel awful. Which is how you know I'm basically good. Right?"
		],
		"human": [
			"I've made an error in judgment. It weighs on me.",
			"The right thing and the done thing diverged. I chose poorly.",
			"I owe amends. A ruler's guilt is a heavy crown.",
			"Forgive me. I haven't forgiven myself yet.",
			"I feel awful. I ate the good cheese.",
			"My conscience won't shut up. Neither will my cheese cravings."
		],
		"elf": [
			"Darling, I've done something... regrettable. Don't pry. ...Pry a little.",
			"Guilt is such an unbecoming color on me. Yet here we are.",
			"The grove knows. It always knows. It's judging me.",
			"I shall make amends. Lavishly. Guilt makes me generous."
		],
		"ogre": [
			"ME DID BAD THING. ME FEEL BAD. ME SORRY.",
			"ME BROKE IT. ME DIDN'T MEAN TO. ME CLUMSY AND SORRY.",
			"GUILT HEAVY. LIKE BIG ROCK ON HEART. ME WANT FIX.",
			"ME APOLOGIZE! ME MAKE IT BETTER! ME PROMISE!"
		]
	},
	"ashamed": {
		"gnome": [
			"Don't look at me. I can't... I can't face anyone right now.",
			"I messed up bad. The kind of bad that echoes.",
			"I'd disappear if I could. Gnomes are good at disappearing. Tempting.",
			"Shame's a bitter drink. I'm drowning in it."
		],
		"human": [
			"I've failed. There's no softer word for it.",
			"The court saw. Everyone saw. I can feel their eyes.",
			"I've let people down. That's the worst of it.",
			"Give me time. I need to earn back my own respect first.",
			"Don't look at me. I cried over spilled cheese.",
			"I can't face this. I CAN face cheese."
		],
		"elf": [
			"I cannot bear to be seen like this, darling. Turn away.",
			"Centuries of grace, undone in a moment. The shame.",
			"Even the flowers look away. I don't blame them.",
			"I shall hide in the grove until the embarrassment fades. See you in a decade."
		],
		"ogre": [
			"ME ASHAMED. ME WANT HIDE UNDER ROCK. BIG ROCK.",
			"ME DID FOOLISH THING. EVERYONE SAW. ME KNOW THEY SAW.",
			"ME SMALL NOW. ME FEEL TINY. ME SORRY.",
			"DON'T LOOK AT ME. ME TOO EMBARRASSED."
		]
	},
	"vengeful": {
		"gnome": [
			"They'll pay. Oh, they'll pay. I've got a ledger and a long memory.",
			"Revenge is a dish best served with interest. Compound interest.",
			"I've been wronged. The scales will balance. I AM the scales.",
			"Smile now. I'll smile later. Last. Longest."
		],
		"human": [
			"Justice will be done. I will personally see to it.",
			"The offense will not stand. The response is being drafted.",
			"I am patient. Vengeance favors the patient. And the well-armed.",
			"They mistook my mercy for weakness. A costly error.",
			"They'll pay. In cheese. All their cheese.",
			"I never forget. Especially cheese debts."
		],
		"elf": [
			"Oh, darling. They have NO idea what's coming. The grove sharpens its thorns.",
			"My revenge will be elegant. It will be devastating. It will be legendary.",
			"I've waited centuries before. I can wait a little longer.",
			"Sweetling, never wrong an elf. We write it in the BARK."
		],
		"ogre": [
			"THEY HURT ME! ME HURT THEM BACK! BIGGER!",
			"ME REMEMBER! ME NEVER FORGET! ME GET EVEN!",
			"VENGEANCE! ME COMING! THEY BETTER RUN!",
			"ME ANGRY FOREVER UNTIL EVEN! THEN ME STILL LITTLE ANGRY!"
		]
	},
	"lovesick": {
		"gnome": [
			"Can't eat. Can't sleep. Keep writing bad poetry. It's serious.",
			"They smiled at me. ME. I've replayed it four hundred times.",
			"Love's got me by the beard and it won't let go.",
			"I'm useless. Hopeless. Smitten. Don't tell them. ...Tell them."
		],
		"human": [
			"I find myself... distracted. By a person. It's most unprofessional.",
			"The court notices nothing. I notice everything about THEM.",
			"I've drafted three love letters. Burned four. The math works.",
			"My heart has staged a coup against my better judgment.",
			"My heart's doing somersaults. So is my cheese.",
			"Completely smitten. Also completely out of cheese. Tragic."
		],
		"elf": [
			"Darling, I am utterly, hopelessly smitten. It's embarrassing. It's wonderful.",
			"The grove blooms where they walk. I've checked. Repeatedly.",
			"I've composed seventeen sonnets. They're all terrible. I'm keeping them.",
			"Love, sweetling, is the finest madness. I've gone completely mad."
		],
		"ogre": [
			"ME HEART GO BOOM! ME THINK ABOUT THEM ALWAYS!",
			"ME LOVESICK! ME CAN'T EAT! ME CAN EAT LITTLE! BUT HEART SICK!",
			"THEY PRETTY! THEY PERFECT! ME WRITE POEM! POEM BAD! ME LOVE ANYWAY!",
			"ME DISTRACTED! ME DREAMING! ME BUMP INTO WALL! WORTH IT!"
		]
	}
}


const ASIDES := {
	"joyful": [
		"I'm grinning like a fool and I don't care.",
		"Best. Day. Ever."
	],
	"content": [
		"All's well in my world.",
		"Can't complain. Won't, either."
	],
	"proud": [
		"I did that, you know.",
		"Pretty impressive, if I say so myself."
	],
	"excited": [
		"I can barely sit still!",
		"Something wonderful is happening!"
	],
	"grateful": [
		"Truly, thank you.",
		"I won't forget this kindness."
	],
	"amused": [
		"Heh. Good one.",
		"That's genuinely funny."
	],
	"sad": [
		"Sorry. Grey day.",
		"Don't mind me."
	],
	"lonely": [
		"It's quiet lately.",
		"Stay a while?"
	],
	"grieving": [
		"Still hurts.",
		"I miss them."
	],
	"angry": [
		"I'm still furious, by the way.",
		"Don't test me today."
	],
	"bitter": [
		"The world's taught me plenty.",
		"Trust is expensive."
	],
	"jealous": [
		"Must be nice.",
		"I've noticed. Oh, I've noticed."
	],
	"afraid": [
		"Stay close, alright?",
		"Something feels wrong."
	],
	"anxious": [
		"My nerves are shot.",
		"I can't settle."
	],
	"stressed": [
		"Too much at once.",
		"I'm at my limit."
	],
	"exhausted": [
		"I'm running on empty.",
		"Barely standing."
	],
	"bored": [
		"Nothing ever happens.",
		"Entertain me. Please."
	],
	"hopeful": [
		"Fingers crossed.",
		"Good things coming. I feel it."
	],
	"guilty": [
		"I feel awful about it.",
		"My conscience won't shut up."
	],
	"ashamed": [
		"Don't look at me.",
		"I can't face this."
	],
	"vengeful": [
		"They'll pay. Oh, they'll pay.",
		"I never forget."
	],
	"lovesick": [
		"My heart's doing somersaults.",
		"Completely, hopelessly smitten."
	]
}


const CHEESE_LINES := [
	"CHEESE! Did somebody say cheese?! I heard cheese!",
	"I dream in cheese. Last night was a gouda one.",
	"Brie is just cheese that went to finishing school.",
	"I would trade my boots for a good stilton. Don't test me.",
	"The moon is made of cheese. I've seen the diagrams.",
	"Cheddar sharp enough to cut through my problems.",
	"You know what this town needs? MORE cheese.",
	"I named my sword 'Brie'. It cuts AND it snacks.",
	"Parmesan is just cheese that lifts weights.",
	"If loving cheese is wrong, lock me up and throw away the rind.",
	"Mozzarella pulls like my heartstrings.",
	"I judge people by their cheese opinions. Most fail.",
	"Blue cheese is just cheese with battle scars. Respect.",
	"A day without cheese is a day I don't count.",
	"I once ate cheese for every meal for a week. Best week.",
	"Gouda news, everyone! ...I'll see myself out.",
	"The cheese shop is my church. I tithe in crumbs.",
	"Swiss cheese has holes because it's thinking about cheese.",
	"I'd fight a dragon for the last wheel. I'd LOSE, but I'd fight.",
	"Cheese before honor. Cheese before EVERYTHING.",
	"My blood type is cheese-positive.",
	"Ask me about my cheese cellar. Please. Nobody asks.",
	"Feta believe it or not, I'm obsessed.",
	"Some people collect coins. I collect cheese regrets. (I ate them all.)"
]


const CHEESE_SCREAMS := [
	"CHEESE!!!",
	"IT'S HAPPENING! THE CHEESE IS HERE!",
	"I CAN SMELL IT! THE BEAUTIFUL CHEESE!",
	"EVERYBODY STAY CALM! ...I CAN'T STAY CALM! CHEESE!",
	"MY KINGDOM FOR A WHEEL OF THAT!",
	"LOOK AT IT! LOOK AT ALL THAT CHEESE!",
	"I'M NOT CRYING, YOU'RE CRYING! IT'S THE CHEESE FUMES!",
	"CHEESE SHOP! CHEESE SHOP! CHEESE SHOP!",
	"SOMEBODY HOLD ME, THERE'S TOO MUCH CHEESE AND NOT ENOUGH ME!",
	"THIS IS THE BEST DAY OF MY LIFE AND I'VE BEEN MARRIED!",
	"FRESH WHEELS! FRESH WHEELS, PEOPLE!",
	"I TAKE IT BACK, HEAVEN IS REAL AND IT SMELLS LIKE THIS!"
]


const FOOD_PRIDE := {
	"gnome": [
		"Tacos beat everything. Gnome science proved it.",
		"A taco a day keeps the doom away."
	],
	"ogre": [
		"TURKEY! BIG BIRD! ME EAT WHOLE!",
		"Me once ate a whole turkey. Me would do it again. Me WILL."
	],
	"elf": [
		"Honeycake, darling. The only civilized dessert.",
		"One simply does not refuse honeycake."
	]
}
