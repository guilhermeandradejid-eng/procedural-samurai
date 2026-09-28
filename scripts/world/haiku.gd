class_name Haiku
extends RefCounted
## Composes a three-line haiku (in Portuguese) from the season and the place,
## like the haiku spots of Ghost of Tsushima.

const FIRST := [
	"Folhas de bordo",
	"Vento de outono",
	"Neve no cume",
	"Lua sobre o lago",
	"Campos dourados",
	"Pétalas caem",
	"Fumaça distante",
	"Silêncio antigo",
]
const MIDDLE := [
	"a lâmina descansa na bainha",
	"o grou atravessa a névoa fria",
	"passos que o capim logo esquece",
	"o sino do templo chama ninguém",
	"sangue lavado pela chuva lenta",
	"a montanha guarda o céu inteiro",
	"um velho caminho sobe sozinho",
	"a água quente conversa com a pedra",
]
const LAST := [
	"e eu, ainda vivo.",
	"o mundo respira.",
	"tudo passa, fica o vento.",
	"honra sem nome.",
	"a casa está longe.",
	"cai a primeira estrela.",
	"a espada lembra.",
	"só resta o agora.",
]


static func compose(seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return "%s —\n%s,\n%s" % [FIRST[rng.randi() % FIRST.size()], MIDDLE[rng.randi() % MIDDLE.size()], LAST[rng.randi() % LAST.size()]]
