# O Samurai de Ezo — Procedural Samurai

Um jogo de mundo aberto em **Godot 4.7** onde você é um samurai "bonequinho gordinho" no estilo
*Human Fall Flat* (cabeção, corpo de ragdoll ativo, armadura, chapéu e katana), explorando uma ilha
inspirada em *Ghost of Tsushima* / *Ghost of Yōtei*: planícies douradas, bordos vermelhos, bambuzais,
lago, litoral e o vulcão Ezo-Fuji. Mundo, texturas, modelos 3D e **todos os sons** são gerados por código
(Python + Blender como módulo `bpy`); as únicas coisas de fora são as **animações prontas e gratuitas**
(KayKit, CC0, e captura de movimento do DeepMimic — veja `assets/motion/CREDITS.md`).

> Combate cheio de *game juice*: golpes com câmera lenta, aparos perfeitos, fatiamento de verdade
> (o corte segue o plano da lâmina e mostra o interior), desmembramento, sangue por todo lado, cabeças que
> quicam com um sonoro **BOING!**, e um pouco de *Devil May Cry*: cada golpe corta o vento (crescente de
> ar que distorce a imagem), deixa imagens residuais nos avanços, o golpe pesado acumula brasas e luz na
> lâmina enquanto você segura o botão, e os golpes fortes borram a tela e "racham" a imagem — sem textos
> na tela atrapalhando a cena.

## Como jogar

```bash
godot --path .          # abre o jogo (Godot 4.7+, renderizador Forward+)
godot --path . -- --play   # pula a tela de título
```

| Ação | Teclado / Mouse | Controle |
|---|---|---|
| Mover / correr / esgueirar | `WASD` / `Shift` / `C` | analógico esq. / L3 / gatilho esq. |
| Golpe leve (combo) | botão esquerdo | X |
| Golpe pesado carregado | segure `E` | Y |
| Bloquear — **aparar** no instante do impacto | botão direito | LB |
| Esquivar (rolar) | `Espaço` | B |
| Travar alvo | `Tab` / botão do meio | R3 |
| Curar (gasta Determinação) | `R` | ↑ |
| Interagir / assassinar por trás | `F` | RB |
| Confronto (duelo à la Tsushima) | `G` | ← |
| Vento Guia | `T` | ↓ |
| Mapa · Pausa | `M` · `Esc` | Back · Start |
| Modo Kurosawa · Ajuda · Estatísticas | `F3` · `F1` · `F4` | |

* **Aparo perfeito / esquiva perfeita** dão câmera lenta e contra-ataque.
* **Confronto**: segure o golpe, solte quando o inimigo *realmente* atacar (cuidado com as fintas).
* **Furtividade**: agache no capim dourado, ataque por trás com `F`.
* **Locais**: santuários (mais Determinação), fontes termais (mais vida), haikus, a árvore sagrada e
  11 acampamentos para libertar. Descubra-os pelo mapa ou siga o Vento Guia.

## O que tem dentro

* **Mundo**: heightmap 2 km × 2 km com erosão hidráulica/térmica, biomas, estradas por A*, lago, mar,
  pontos de interesse; terreno com LOD, água, ~18 mil árvores e 13 mil rochas (MultiMesh com LOD por
  instância, colisão por streaming), grama e pampas por partículas GPU, vento global.
* **Céu e clima**: ciclo dia/noite, sol com raios, nuvens em três camadas (cúmulos iluminados por várias
  amostras, altocúmulos, cirros), Via Láctea, estrelas cadentes, aurora, lua com crateras; névoa volumétrica
  rente ao solo, chuva com respingos, poças com ondulações, relâmpagos que iluminam nuvens e neblina;
  grama que pende molhada, personagens ensopados e gotas na lente da câmera.
* **Personagens**: ragdoll ativo (corpo físico que persegue poses-alvo) tocando **clipes de animação
  esquelética prontos** (KayKit CC0 para golpes, guarda, reações e levantar; captura de movimento real
  para andar/correr/rolar) retargetados para o boneco chibi, com stride warping, orientation warping,
  inertialization, pés presos ao terreno por IK e empunhadura de duas mãos; armaduras/kabuto/kasa/katana
  modelados em Blender. Veja `docs/animacao.md`.
* **Combate**: combos, carga, bloqueio/aparo, rolamento com i-frames, ímã de golpe, atordoamento,
  desmembramento e **fatiamento por plano** com shader de corte. Efeitos à la *Devil May Cry*: crescente
  de vento com refração, fita de ar atrás da lâmina, imagens residuais, desfoque radial, linhas de
  velocidade, o "corte" que racha a tela nos golpes fortes, brasas e luz na lâmina durante a carga do golpe
  pesado (com anel e som ao chegar no máximo), sangue na lente que escorre e some e um quadro de impacto
  em preto, branco e vermelho nos golpes mortais e na última morte de uma luta (opções: *Efeitos de
  combate* e *Desfoque de movimento*). As lâminas varrem um volume com espessura, então o golpe que
  encosta visualmente no alvo acerta.
* **IA**: percepção por visão/ruído, alerta em grupo, fichas de ataque (poucos atacam por vez), fintas,
  golpes telegrafados (lâmina em brasa vermelha = imbloqueável), fuga, patrulhas.
* **Áudio 100 % sintetizado**: espadas, carne, vozes, sinos, taiko + shakuhachi + koto, ambientes.
* **Interface**: HUD com pincelada, indicadores de detecção (o golpe imbloqueável ganha um triângulo de
  alerta vermelho em vez de texto), mapa de pergaminho, pausa, opções, morte.

## Gerando os assets (já estão versionados)

```bash
pip install numpy scipy pillow soundfile bpy==4.5.4
python3 tools/worldgen/generate_world.py     # mundo (heightmap, biomas, estradas, POIs)
python3 tools/worldgen/scatter.py            # árvores e rochas
python3 tools/textures/generate_textures.py  # texturas procedurais
python3 tools/blender/build_models.py        # modelos 3D (Blender como módulo)
python3 tools/audio/synth_all.py             # sons e músicas
python3 tools/motion/build_all.py            # clipes de animação (assets/motion)
python3 tools/project/make_project.py        # project.godot
godot --headless --path . --import
python3 tools/project/fix_imports.py         # texture arrays, loops de áudio
```

## Testes e ferramentas de desenvolvimento

```bash
godot --headless --path . --script res://tests/check_scripts.gd     # compila todos os scripts
godot --headless --path . res://tests/hit_test.tscn                 # precisão dos golpes por arma
godot --headless --path . res://tests/ai_test.tscn                  # IA em combate
godot --headless --path . -- --play --autotest <dir>                # bot joga no mundo real
xvfb-run godot --path . --rendering-driver vulkan res://tests/pose_gallery.tscn -- <dir>
python3 tests/make_sheet.py <dir> <prefixo>                          # folha de poses
godot --path . -- --tour <dir> --weather storm --time 17.5          # capturas do mundo (views: sun, moon, ...)
python3 tools/motion/check_clips.py                                  # sanidade dos clipes de animação
godot --headless --path . res://tests/track_test.tscn               # erro (cm) entre o clipe e o ragdoll, por ação
```

Variáveis do `--autotest`: `AUTOTEST_MODE=standoff|assassinate`, `AUTOTEST_FRAMES`, `AUTOTEST_APPROACH`.
