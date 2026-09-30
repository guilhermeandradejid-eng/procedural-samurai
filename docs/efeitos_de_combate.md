# Efeitos de combate (game juice)

Tudo é código: shaders em `shaders/`, partículas e malhas geradas em tempo de execução por `scripts/autoload/fx.gd`,
sons sintetizados em `tools/audio/sfx.py`. Os dois controles em *Opções* mexem em quase tudo daqui:
**Efeitos de combate** (`combat_fx`, 0 desliga os efeitos novos) e **Desfoque de movimento** (`motion_blur`).

| Efeito | Quando aparece | Onde está |
|---|---|---|
| **Crescente de vento**: meia-lua de ar que sai da lâmina, entorta a imagem atrás dela (refração), levanta poeira e deixa filetes de ar | no instante mais rápido de cada golpe (o tamanho segue o `power` do golpe); estocadas só soltam filetes | `FX.wind_slash`, `shaders/wind_slash.gdshader`, `Character._swing_juice` |
| **Fita de ar** atrás da lâmina | durante a janela ativa do golpe | `SlashTrail` (`material_overlay`), `shaders/air_ribbon.gdshader` |
| **Imagens residuais** (cópias translúcidas do corpo) | avanços dos golpes do jogador, rolamento, corrida rápida e golpes de força ≥ 1,6 | `FX.afterimage`, `shaders/afterimage.gdshader`, `Character._ghost_trail` |
| **Desfoque radial** (zoom) em direção ao ponto de impacto | golpes fortes, acertos e carga completa | `Game.radial_blur`, `shaders/post_fx.gdshader`, `PostFX._update_juice` |
| **Linhas de velocidade** nas bordas | corrida rápida, rolamento, avanço do golpe | `Game.speed_fx`, `Player._think` |
| **Corte na tela**: a imagem se abre ao longo do golpe e fecha de novo | abates e golpes de força ≥ 1,6 | `Game.slash_line`, `PostFX` |
| **Carga do golpe pesado**: brasas e luz quente na lâmina que crescem com o tempo; ao chegar no máximo, um anel, um "shing" e um pulso de zoom | enquanto o botão de golpe pesado está apertado | `Weapon.charge`, `FX.ember_emitter`, `Player._charge_pop`, som `charged` |
| **Lâmina em brasa vermelha** | espera dos golpes perigosos (imbloqueáveis) dos inimigos | `Enemy._combat` (usa `Weapon.charge` com `PERIL_COLOR`) |
| **Sangue na lente**: manchas irregulares com gotas satélites que escorrem e encolhem até sumir | golpes, abates e desmembramentos perto da câmera | `Game.lens_splash`, `lens_drops` em `shaders/post_fx.gdshader` |
| **Quadro de impacto** em preto, branco e vermelho por 3 a 4 quadros | golpe mortal (postura quebrada) e a última morte de uma luta | `Game.impact_frame`, `shaders/post_fx.gdshader` |
| Parada de tempo, câmera lenta, tremor, coice de campo de visão, faíscas, anéis de choque, fatiamento por plano | como antes | `Game`, `CameraRig`, `FX` |

## Como ver sem jogar

`tests/juice_shots.tscn` renderiza quadros parados com a câmera e o pós-processamento do jogo:

```bash
xvfb-run -a godot --path . --rendering-driver vulkan --resolution 960x540 res://tests/juice_shots.tscn -- <pasta> \
    light_1,heavy,counter        # golpes: crescente, imagens residuais, desfoque, corte
xvfb-run ... res://tests/juice_shots.tscn -- <pasta> charge   # carga, brilho vermelho do inimigo, sangue na lente
xvfb-run ... res://tests/juice_shots.tscn -- <pasta> impact   # quadro de impacto
```

## Onde ajustar a intensidade

* `Character._swing_juice`: tamanho do crescente (`0.75 + power * 0.32`), quando há imagem residual e desfoque.
* `Player.hit_landed` (em `player.gd`): desfoque e corte da tela ao acertar.
* `FX.ember_emitter` / `Weapon.charge`: quantidade de brasas, alcance e força da luz.
* `lens_drops` (`post_fx.gdshader`): tamanho, quantidade e desgaste das gotas na lente.
