# Animação: de onde vêm os movimentos

O boneco é um **ragdoll ativo** (o corpo físico persegue poses-alvo), e as poses-alvo vêm de
**clipes de animação esquelética prontos** em `assets/motion/*.json`. O jogo só toca os clipes, mistura
entre eles e adapta ao terreno; quem prepara os clipes é o pipeline em `tools/motion/`.

## Fontes (todas gratuitas)

| Clipes do jogo | Fonte | Licença |
|---|---|---|
| ataques de katana / kanabo / lança (`katana_*`, `kanabo_*`, `yari_*`), guarda com duas mãos (`guard_idle`), parado (`idle`), golpe recebido (`hit_f`), cambaleio (`stagger`), levantar (`getup`), sentar (`sit`) | **KayKit – Adventurers Character Pack** (Kay Lousberg), 76 animações em glTF | CC0 |
| andar, correr, correr rápido, agachado, rolar (`walk`, `run`, `sprint`, `crouch_walk`, `roll`) | captura de movimento real do **DeepMimic**, distribuída com o pacote `pybullet_data` | zlib (o DeepMimic é MIT, mas não documenta a origem da captura original: confira antes de distribuir comercialmente) |
| bloqueio, aparo, reações laterais/por trás, sacar/limpar a espada, oração, cura, pose de confronto | poses-chave autorais (`tools/motion/clips_*.py`) | do projeto |

Créditos: `assets/motion/CREDITS.md`.

## Retarget (`tools/motion/kaykit.py`)

O esqueleto do KayKit (T-pose, cabeça grande) é aplicado ao rig chibi de 16 partes:

* **rotações no espaço do mundo**: o quanto cada osso girou em relação ao repouso é aplicado à parte
  correspondente; os braços levam uma correção fixa (T-pose → braços caídos, o menor arco);
* **quadril**: o centro das articulações do quadril segue a animação, com deslocamentos multiplicados
  pela razão do comprimento das pernas e ancorado no tornozelo (os pés continuam no chão);
* **espada**: a pose da espada (ou da mão direita, nas animações sem arma) vira uma **empunhadura de
  duas mãos no referencial do peito**; o jogo resolve os dois braços até ela, então as duas mãos
  ficam no cabo mesmo com braços mais curtos que os do original. O offline mantém os pulsos dentro do
  alcance e solta a mão esquerda quando não dá;
* **giros** (`2H_Melee_Attack_Spinning`, `_Spin`): a rotação do corpo é removida do clipe e o jogo
  gira o personagem inteiro (`"spin"` em `AttackLibrary`), assim os pés presos giram junto;
* **contatos dos pés** vêm da altura e velocidade dos tornozelos; o instante do golpe
  (`meta.strike`) é o pico de velocidade da ponta da lâmina (ou o alcance máximo, nas estocadas).

Também dá para assar um ciclo de andar/correr do KayKit (`kaykit.py cycle <clipe> <animação>`), começando
no apoio do pé direito e com a velocidade nativa medida. Foi comparado com a captura do DeepMimic no boneco
chibi e a captura ficou: o andar e o correr do KayKit deixam os braços abertos demais para essas
proporções, enquanto a captura balança os braços de forma natural.

## Como o jogo usa os clipes

* `MotionClip` / `MotionPose` (GDScript): amostragem por frame com slerp; cada clipe guarda a posição
  do quadril, uma rotação local por parte do rig, contatos dos pés e (para armas) a empunhadura no
  referencial do peito.
* `ProceduralAnimator`:
  * locomoção: *idle / walk / run / sprint* misturados por velocidade numa fase de passada comum,
    com **stride warping** e **orientation warping** (andar de lado/de costas), inclinação nas curvas;
  * ações (ataques, defesa, rolamento, reações...): o clipe é escolhido pela ação; a troca usa
    **inertialization** (o deslocamento entre a pose anterior e a nova decai);
  * pés: os contatos do clipe fixam os pés no terreno real (raycast + IK de duas juntas); o joelho
    dobra no mesmo plano do clipe (o eixo do joelho vem da coxa do clipe, não da posição do joelho);
  * braços: FK do clipe, ou IK de duas juntas até a empunhadura de duas mãos;
  * cabeça: olhar para o alvo por cima do clipe.
* `AttackLibrary` guarda só a parte de jogo de cada golpe (dano, janela ativa, avanço, `hit_reach`,
  `aim_yaw`); o clipe traz a pose. O instante do golpe do clipe é alinhado ao meio da janela ativa.
  `aim_yaw` (graus, positivo = esquerda) vira o corpo um pouco para o lado quando o clipe corta fora do
  eixo do corpo (o contra-ataque é um talho da mão direita).
* Acerto: a cada quadro físico seis pontos da lâmina lançam raios entre a posição anterior e a atual, e
  mais dois raios de cada lado da superfície varrida (a lâmina tem espessura: 11 cm para o jogador,
  5 cm para os inimigos). Sem isso, um golpe horizontal passava pelo vão entre o pescoço e o ombro.
  `tests/hit_test.tscn` mostra a matriz de acertos por distância (`ONLY=player/counter` filtra).

## Corpo físico

O ragdoll segue o clipe de perto porque:

* as dobradiças de cotovelo e joelho usam os limites com o sinal que o Jolt mede (`[-150, 5]` para
  antebraços e `[-5, 150]` para canelas): antes estavam espelhados e os membros mal dobravam;
* o punho é uma junta larga (110°/90°), para a mão acompanhar a empunhadura;
* enquanto um membro é conduzido ele usa um material **escorregadio**; ao ficar mole, morrer ou ser
  cortado volta ao material de atrito alto (senão a ponta do pé raspava no chão na fase de balanço).

`tests/track_test.tscn` mede, para cada ação, o erro (cm) entre onde o clipe quer cada grupo do
corpo e onde o ragdoll está: andar 37 → 10 cm de erro máximo (média 9 → 1,7 cm), mãos 13–19 → 0,5 cm.

## Pipeline offline (`tools/motion/`)

```bash
pip install numpy scipy matplotlib pybullet   # pybullet só para extrair a captura do DeepMimic
export KAYKIT_DIR=<KayKit-Character-Pack-Adventures-1.0>/addons/kaykit_character_pack_adventures/Characters/gltf
python3 tools/motion/build_all.py             # gera tudo em assets/motion (DM_MOTIONS=<pybullet_data/data/motions>)
python3 tools/motion/kaykit.py list           # animações disponíveis no pacote
python3 tools/motion/kaykit.py build guard_idle light_1   # refaz só alguns clipes
python3 tools/motion/check_clips.py           # emenda de loops, saltos de rotação, chão
```

* `gltf_reader.py`: leitor mínimo de GLB (esqueleto e animações), sem dependências além de numpy.
* `kaykit.py`: o retarget e a lista `CLIPS` (nome do clipe do jogo → animação de origem, corte, opções).
* `mo_rig.py`: cinemática direta do rig real (`rig.json`, o mesmo do jogo), IK de duas juntas.
* `dm_import.py`, `locomotion.py`, `posefx.py`: retarget da captura do DeepMimic, contatos, calibração
  do chão, corrida → sprint, andar → agachado.
* `authoring.py`, `kit.py`, `clips_*.py`: poses-chave autorais (bloqueio, aparo, reações...).
* `preview.py`: folhas de contato (boneco de palitos com as proporções reais) para revisar sem a engine.
