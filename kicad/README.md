# KiCAD-Projekt-Ordner

## Was hier liegt

| Datei | Zweck |
|-------|-------|
| `atari_ulx3s_adapter.kicad_pro` | Projektfile, mit KiCAD 8+ öffnen |
| `atari_ulx3s_adapter.kicad_sch` | Schematic-Startversion (8 Komponenten platziert, keine Drähte) |
| `atari_ulx3s.kicad_sym` | Custom Symbol Library (4 Symbole, verifiziert) |
| `sym-lib-table` | Library-Tabelle, damit KiCAD die Custom-Lib findet |

## So öffnest du das Projekt

1. **KiCAD 8 oder neuer** starten
2. Project File öffnen: `atari_ulx3s_adapter.kicad_pro`
3. KiCAD wird die Custom-Library aus `sym-lib-table` automatisch laden
4. Schematic Editor öffnen (Doppelklick auf Schematic-Eintrag oder F1)

## Was du im Schematic siehst

8 Komponenten in 3 Spalten platziert:

- **Links:** Atari Cart Edge Connector (J1) — 40-pin Edge-Connector
- **Mitte:** 5× 74LVC4245A (U1–U5) übereinander
- **Rechts:** ULX3S J1 Socket (J2) oben, ULX3S J2 Socket (J3) unten

Keine Drähte — du zeichnest die Verbindungen nach `03_netlist_connections.md`.

## Was du noch hinzufügen musst (aus KiCAD-Standard-Libs)

Diese Komponenten habe ich NICHT in der Custom-Lib generiert, weil sie aus KiCAD-Standard-Bibliotheken kommen (Device, Switch, Connector_Generic, power):

- **R1, R2** — 10 kΩ Pullup nach +5V_BUS (für DOE_N und DIR_D)
- **R3, R4** — 1 kΩ Vorwiderstände für Status-LEDs
- **C1** — 10 µF Tantal Bulk (5V-Schiene)
- **C2** — 10 µF (3.3V-Schiene)
- **C3–C12** — 100 nF Decoupling (2 pro Shifter, je 1× VCCA + 1× VCCB)
- **D1, D2** — LED grün/rot für USB/Atari Power-Indikator
- **SW1** — SPDT Slide-Switch (z.B. `Switch:SW_SPDT`)
- **TP1–TP5** — Test-Points für U3 Reserve-Pins
- **Power-Flags** — `+5V`, `+3V3`, `GND` (aus `power` Library)
- **Power-Nets** (Custom-Labels):
  - `+5V_BUS` (nach SW1 Common)
  - `+5V_USB` (zwischen ULX3S J2-5V-Pin und SW1)
  - `+5V_ATARI` (zwischen Atari Cart Pin 1+2 und SW1)

## Verdrahtungs-Recipe

Folge der Tabelle in `../03_netlist_connections.md`. Für jeden Atari-Pin:

1. Setze einen Wire vom Cart-Pin (links) auf einen 74LVC4245A-A-Pin (Mitte)
2. Vom B-Pin (3.3V-Seite) auf den ULX3S-Header-Pin (rechts)
3. Beide Wire-Endpunkte können auch ein Net-Label bekommen — KiCAD verbindet alles mit gleichem Label

Alternativ (schneller): mit `Add Label` einen Net-Namen auf jeden Pin packen.
Z.B. an Cart-Pin 36 (A1) Label "A1", an U1-Pin 3 (A1-Eingang) auch "A1" — KiCAD
verbindet die beiden ohne Wire-Routing.

## Power-Anschlüsse (Beispiel-Wires)

```
Cart J1 Pin 1   ── +5V_ATARI ──┐
Cart J1 Pin 2   ── +5V_ATARI ──┴── SW1 Pin 2

ULX3S J2 Pin 1  ── +5V_USB ────┐
ULX3S J2 Pin 2  ── +5V_USB ────┴── SW1 Pin 1

SW1 Pin 3       ── +5V_BUS ────┬── U1 VCCA (Pin 1)
                                ├── U2 VCCA
                                ├── U3 VCCA
                                ├── U4 VCCA
                                ├── U5 VCCA
                                ├── R1 (Pullup DOE_N)
                                ├── R2 (Pullup DIR_D)
                                └── ULX3S J2 Pin 1 (zurück, mit Schottky D1)

ULX3S J1 Pin 1  ── +3V3 ───────┬── U1 VCCB (Pin 23, 24)
                                ├── U2..U5 VCCB
                                └── Decoupling Caps

GND             ── globaler Net, alle GNDs verbinden
```

## ERC-Tipps

Nach dem Verdrahten:
1. **Inspect → Run Electrical Rules Checker (ERC)** ausführen
2. Häufige Warnings:
   - "Pin not connected" auf den NC- oder Reserve-Pins → bei TP1–TP5 absichtlich; Markieren mit "Add no-connect flag"
   - "Power input not driven" → Power-Flag fehlt; ein `(power)` Symbol pro Power-Net hinzufügen
3. Fehler **dürfen nicht** vorhanden sein — wenn doch, im Pinout (Doc 03) gegenchecken

## Beim Übergang zu PCB-Layout (Phase 5)

1. Im Schematic: **Tools → Update PCB from Schematic** (F8)
2. Dabei werden die Footprints aus den `Footprint`-Properties geladen:
   - `Package_SO:SSOP-24_5.3x8.2mm_P0.65mm` für 74LVC4245A
   - `Connector_PinSocket_2.54mm:PinSocket_2x20_P2.54mm_Vertical` für ULX3S-Header
   - `atari_ulx3s_adapter:CartEdge_40Pin_ST` — den müssen wir noch erzeugen (Custom Footprint für den Atari-Edge-Connector)
3. Pull-/Cap-/LED-/Switch-Footprints werden automatisch aus den KiCAD-Standard-Footprint-Libs gezogen

## Bei Fragen

Schau in die Phase-Docs im Parent-Ordner:
- `01_pinout_signal_analyse.md` — Signal-Bedeutung
- `02_levelshifter_und_power.md` — Power-Strategie + Switch
- `03_netlist_connections.md` — exakte Net-Liste (das Master-Doc für Verdrahtung)
- `04_pin_verification_findings.md` — was bei Verifikation gefixt wurde
- `Doku/ulx3s_J1_J2_pinout.md` — physische ULX3S-Pin-Belegung
