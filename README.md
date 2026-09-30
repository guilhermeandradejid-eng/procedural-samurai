# O Samurai de Ezo — Procedural Samurai

Um jogo de mundo aberto em **Godot 4.7** onde você é um samurai "bonequinho gordinho" no estilo
*Human Fall Flat* (cabeção, corpo de ragdoll ativo, armadura, chapéu e katana), explorando uma ilha
inspirada em *Ghost of Tsushima* / *Ghost of Yōtei*: planícies douradas, bordos vermelhos, bambuzais,
lago, litoral e o vulcão Ezo-Fuji. Tudo — mundo, texturas, modelos 3D e **todos os sons** — é gerado por
código (Python + Blender como módulo `bpy`), sem nenhum asset externo.

> Combate cheio de *game juice*: golpes com câmera lenta, aparos perfeitos, fatiamento de verdade
> (o corte segue o plano da lâmina e mostra o interior), desmembramento, sangue por todo lado, cabeças que
> quicam com um sonoro **BOING!**, onomatopeias em quadrinhos e muito exagero.

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
* **Personagens**: ragdoll ativo (corpo físico que persegue animações procedurais: marcha, IK de pés e
  braços, golpes por keyframes de espada), armaduras/kabuto/kasa/katana modelados em Blender.
* **Combate**: combos, carga, bloqueio/aparo, rolamento com i-frames, ímã de golpe, atordoamento,
  vento/desmembramento e **fatiamento por plano** com shader de corte.
* **IA**: percepção por visão/ruído, alerta em grupo, fichas de ataque (poucos atacam por vez), fintas,
  golpes telegrafados (brilho vermelho = imbloqueável), fuga, patrulhas.
* **Áudio 100 % sintetizado**: espadas, carne, vozes, sinos, taiko + shakuhachi + koto, ambientes.
* **Interface**: HUD com pincelada, indicadores de detecção, mapa de pergaminho, pausa, opções, morte.

## Gerando os assets (já estão versionados)

```bash
pip install numpy scipy pillow soundfile bpy==4.5.4
python3 tools/worldgen/generate_world.py     # mundo (heightmap, biomas, estradas, POIs)
python3 tools/worldgen/scatter.py            # árvores e rochas
python3 tools/textures/generate_textures.py  # texturas procedurais
python3 tools/blender/build_models.py        # modelos 3D (Blender como módulo)
python3 tools/audio/synth_all.py             # sons e músicas
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
godot --path . -- --tour <dir> --weather storm --time 17.5          # capturas do mundo
```

Variáveis do `--autotest`: `AUTOTEST_MODE=standoff|assassinate`, `AUTOTEST_FRAMES`, `AUTOTEST_APPROACH`.
