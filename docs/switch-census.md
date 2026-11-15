# Перепись switch в портируемом C (2026-11-15)

Источник: C-IR (дамп clang до любого понижения), не вывод das. Скрипт `metrics/switch_census.das`,
определения признаков и классов в `metrics/ARCHITECTURE_SWITCH.md`, тест
`metrics/tests/test_switch_census.das`. Конвертер на `origin/main` c397b63, daScript по пину.
Запуск: `heavy --label switch-census --max 8G -- prlimit --as=3221225472:6442450944 das
metrics/switch_census.das` (около 13 минут, новых замеров скорости нет).

## Кратко

- В восьми портируемых программах 428 switch; 394 (92%) это S1: целые или enum константы, без
  настоящего провала. Настоящий провал в 29 (7%), goto в другой case в 5 (1%: Lua 3, Quake 2),
  не целого условия нет (C его запрещает), Duff's device и прыжка через объявление в программах
  нет (есть только в тестовых наборах: 3 switch).
- Горячих switch (в функциях из верха существующих профилей) 10, из них S1 8. Но главный из них,
  диспетчер `luaV_execute` (83 опкода, 67-87% времени Lua), это S3: пять `goto` в другой case.
  Второй не-S1: `ppu_synchronize` в binjgb, один настоящий провал.
- Ноды "константы, без fallthrough, несколько значений на ветку" хватило бы для 92% всех switch
  и 8 из 10 горячих. Диспетчеру Lua она не поможет без `goto` между ветками: ему нужна либо нода
  с метками внутри, либо нынешний `--switch-dispatch goto`.
- Без ноды JIT уже делает таблицу из цепочки там, где нет флаговых case: в `luaV_execute` для 69
  опкодов из 83 (до 0x44, F88), остальные 14 идут сравнениями; goto-режим даёт таблицу на все 83
  (fib 2.50x -> 2.02x от native, nbody 1.34x -> 1.05x).

## Таблица

Доли от числа switch программы. "Горячих": switch в функции, у которой 1% и больше собственного
времени в профиле из `perf/profiles/` (native, JIT или интерпретатор).

| программа | switch всего | S1 | S2 | S3 | S4 | горячих | из них S1 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Lua (lua + luac) | 96 | 82 (85%) | 11 (11%) | 3 (3%) | 0 | 3 | 2 |
| PureDOOM | 99 | 94 (95%) | 5 (5%) | 0 | 0 | 0 | 0 |
| doomgeneric | 94 | 88 (94%) | 6 (6%) | 0 | 0 | 0 | 0 |
| quakegeneric | 55 | 52 (95%) | 1 (2%) | 2 (4%) | 0 | нет профиля | - |
| binjgb | 32 | 29 (91%) | 3 (9%) | 0 | 0 | 4 | 3 |
| wasm3 | 22 | 22 (100%) | 0 | 0 | 0 | нет профиля | - |
| h264bsd-mp4 | 28 | 25 (89%) | 3 (11%) | 0 | 0 | 2 | 2 |
| plmpeg-stream | 2 | 2 (100%) | 0 | 0 | 0 | 1 | 1 |
| **программы вместе** | **428** | **394 (92%)** | **29 (7%)** | **5 (1%)** | **0** | **10** | **8** |
| c-testsuite (не реальный код) | 18 | 16 (89%) | 0 | 2 (11%) | 0 | - | - |
| gcc-torture (не реальный код) | 53 | 50 (94%) | 1 (2%) | 2 (4%) | 0 | - | - |

Что стоит за классами (программы вместе, 428):

- Условие: целое 258, enum 137, char 33 (метки записаны символами), `_Bool` 0.
- Значений case: меньше 4 у 144 switch, 4-7 у 177, 8 и больше у 107; из последних 65 заполняют
  диапазон [lo, hi] хотя бы наполовину. `default` есть у 275, не последним стоит у 8.
- Пустой провал (несколько меток на одно тело, `case (1, 2)`) в 161 switch. Настоящий провал
  в 30 (29 класса S2 и `str_format` класса S3). Из 29 три проваливаются только на бумаге: перед
  следующей меткой стоит вызов без возврата (`luaG_opinterror`, `I_Error`, `Host_EndGame`),
  C-IR атрибут `noreturn` не хранит.
- Провал в ветку, где только `break` (`case X: f(); default: break;`), в 14 switch; он равен
  выходу из switch и считается S1.
- Внутри S1 (394): 366 обходятся вообще без `break` (каждая ветка кончается `break`, `return`,
  `goto` наружу или `continue`); в 17 есть `break` не в конце ветки (под `if`); в 12 провал в
  `break`.
- `break` цикла, вложенного в case: 3 switch (`EV_DoFloor` в обоих Doom, один в h264bsd). `continue` из switch
  к внешнему циклу: 0 в программах, 1 в gcc-torture.
- `goto` в другой case: 5 (Lua `luaV_execute`, `match`, `str_format`; Quake `M_Setup_Key`,
  `M_SerialConfig_Key`). Метка внутри case, в которую прыгают извне switch: 0. `goto` из switch
  наружу (обычная метка функции, классу не мешает): 14.
- Объявление на уровне тела switch, видимое в следующем case: 1 (binjgb), следующий case его не
  читает ни разу: 0 прыжков через объявление, которые надо уметь.
- Case во вложенном блоке (Duff's device): 0 в программах; 2 в c-testsuite, 1 в gcc-torture.

Горячие switch и таблица в JIT без ноды (только имеющиеся данные: F88, P7.0p, профиль binjgb):

| switch | значений | класс | сегодня в das | таблица в JIT |
| --- | --- | --- | --- | --- |
| Lua `luaV_execute` (lvm.c:1184) | 83 | S3 | цикл с флагом, 77 простых case и 6 флаговых | частично: 69 опкодов таблицей, 14 (от 0x45) сравнениями; ассемблер, F88 |
| Lua `luaD_precall`, `moveresults` | 3 и 3 | S1 | if-цепочка | таблица не нужна: 3 сравнения и в C |
| binjgb `execute_instruction`: опкоды и CB | 245 и 256 | S1 | if-цепочка | да по косвенным данным: функция в JIT 0.98 от native по сэмплам; ассемблера нет |
| binjgb `execute_instruction`: CpuState | 6 | S1 | if-цепочка (после P7.0zc) | мало значений |
| binjgb `ppu_synchronize` | 13 | S2 | цикл с флагом | нет данных; функция в JIT 1.37 от native, причиной названы проверки null, не switch |
| h264bsd `h264bsdInterPrediction` (2 switch) | 4 и 3 | S1 | if-цепочка | мало значений |
| plmpeg `plm_video_process_macroblock` | 8 | S1 | if-цепочка | нет данных |

Итого по горячим: подтверждённо таблицей идёт 1 из 10, и тот на 69 из 83 case; ещё 2 таблицей
по косвенным данным; у 5 по 3-6 значений, таблица там ничего не даёт; по 2 данных нет. В Doom
горячих switch нет: в функциях рендера их нет вовсе. Цена цепочки в интерпретаторе известна
только по Lua: goto-таблица быстрее в 1.38-1.98 раза (fib 30, binary_trees, nbody,
spectral_norm), в JIT в 1.09-1.32 раза.

## Примеры S2 и S3

Набросок ноды нейтральный: `switch (x) { case (1, 2) { } default { } }`, только константы, без
провала. Где её не хватает, остаётся нынешний макрос `c_switch` (в нём ветка без `break`
проваливается в следующую) или понижение в цикл с флагом.

**S2, Lua, `luaK_finish` (lcode.c:1853): условный провал.**

```c
switch (GET_OPCODE(*pc)) {
  case OP_RETURN0: case OP_RETURN1: {
    if (!(fs->needclose || p->is_vararg))
      break;  /* no extra work */
    SET_OPCODE(*pc, OP_RETURN);
  }  /* FALLTHROUGH */
  case OP_RETURN: case OP_TAILCALL: {
    if (fs->needclose) SETARG_k(*pc, 1);
    if (p->is_vararg) SETARG_C(*pc, p->numparams + 1);
    break;
  }
  case OP_JMP: { fixjump(fs, i, finaltarget(p->code, i)); break; }
  default: break;
}
```

С нодой "только S1" весь switch остаётся `c_switch`:

```
c_switch (GET_OPCODE(*pc)) {
    case (OP_RETURN0, OP_RETURN1) { if (...) { break }; SET_OPCODE(*pc, OP_RETURN) }  // провал
    case (OP_RETURN, OP_TAILCALL) { ...; break }
    case (OP_JMP) { ...; break }
    case (_) { break }
}
```

**S2, Doom, `T_MoveCeiling` (p_ceilng.c:77): одна ветка добавляет действие и проваливается.**

```c
switch (ceiling->type) {
  case raiseToHighest:
    P_RemoveActiveCeiling(ceiling);
    break;
  case silentCrushAndRaise:
    S_StartSound((mobj_t*)&ceiling->sector->soundorg, sfx_pstop);
  case fastCrushAndRaise:
  case crushAndRaise:
    ceiling->direction = -1;
    break;
  default:
    break;
}
```

```
c_switch (ceiling.type) {
    case (raiseToHighest) { P_RemoveActiveCeiling(ceiling); break }
    case (silentCrushAndRaise) { S_StartSound(...) }                  // провал
    case (fastCrushAndRaise, crushAndRaise) { ceiling.direction = -1; break }
    case (_) { break }
}
```

Соседний switch того же файла (p_ceilng.c:175, провал только в `default: break`) уже S1 и лёг
бы в ноду как есть:

```
switch (type) {
    case (fastCrushAndRaise, silentCrushAndRaise, crushAndRaise) { P_ActivateInStasisCeiling(line) }
    default { }
}
```

**S3, Lua, `match` (lstrlib.c:575): `goto` в `default` из двух case.**

```c
switch (*p) {
  case '(': { ...; break; }
  case ')': { s = end_capture(ms, s, p + 1); break; }
  case '$': {
    if ((p + 1) != ms->p_end)
      goto dflt;                      /* в default */
    s = (s == ms->src_end) ? s : NULL;
    break;
  }
  case L_ESC: { switch (*(p + 1)) { ...; default: goto dflt; } break; }
  default: dflt: { ... }
}
```

Ни нода S1, ни `c_switch` этого не берут: метка `dflt` лежит в другой ветке. Сегодня это цикл
с флагом и переменной `_goto` (повторная диспетчеризация), под `--switch-dispatch goto` плоский
набор меток:

```
var _goto = 0
while (true) {
    label 1:  // re-dispatch
    var _flag = false
    if (_cond == '(') { ...; break }
    ...
    if (_cond == '$') { if (...) { _goto = 1; goto label 1 }; ...; break }
    _flag ||= _goto == 0 && !(_cond == '(' || _cond == ')' || _cond == '$' || _cond == '%')
    _flag ||= _goto == 1  // dflt
    if (_flag) { _goto = 0; ... }
    break
}
```

**S3, Lua, `luaV_execute` (lvm.c:1184): опкод прыгает в тело соседнего.**

```c
vmcase(OP_TFORPREP) {
  StkId ra = RA(i);
  halfProtect(luaF_newtbcupval(L, ra + 3));
  pc += GETARG_Bx(i);
  i = *(pc++);  /* go to next instruction */
  goto l_tforcall;
}
vmcase(OP_TFORCALL) {
 l_tforcall: {
  StkId ra = RA(i);
  ...
```

Таких `goto` в диспетчере пять (`l_tforcall`, `l_tforloop`, три `ret`); из-за них 6 case из 83
флаговые, и на первом из них кончается таблица LLVM (F88). Ноде, чтобы взять этот switch,
нужна метка внутри ветки, до которой достаёт `goto` из другой ветки.

**S3 в Doom нет**: 0 из 99 (PureDOOM) и 0 из 94 (doomgeneric).

## Что не удалось классифицировать

- В программах: ничего, все 8 сконвертировались целиком, каждый switch получил класс.
- Горячесть для wasm3 и quakegeneric: профилей нет (у quakegeneric нет и bench), их switch
  посчитаны, но ни один не помечен горячим. У wasm3 диспетчер опкодов не switch, а вызовы
  функций операций в хвостовой позиции; у Quake вероятный кандидат `PR_ExecuteProgram`.
  doomgeneric своего профиля не имеет, взяты имена функций из профиля PureDOOM.
- c-testsuite: из 220 файлов дампер не взял 10, слово `switch` есть в одном (00213, GNU
  statement expression).
- gcc-torture: из 1656 файлов дампер не взял 314, слово `switch` есть в 17: K&R и неявный `int`
  (6), вложенные функции (2), векторные типы (2), указатель или массив `va_list` (2), inline asm
  с операндами (2), GNU-диапазон `case 1 ... 3` (1, pr34154), `&&label` (1),
  `__builtin_va_arg_pack` (1). Диапазон case конвертер не поддерживает вовсе, в программах его
  нет.
- Настоящий провал определяется по тексту: вызов функции без возврата в конце ветки не
  распознаётся (три таких случая названы выше).
- "Горячий switch" значит switch в горячей функции; холодный switch внутри такой функции тоже
  считается горячим (в `luaD_precall` и `execute_instruction` это так и есть для части строк
  таблицы).
