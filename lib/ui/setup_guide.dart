import 'package:flutter/material.dart';

import 'controls.dart';
import 'strings.dart';

class SetupGuide extends StatelessWidget {
  const SetupGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final steps = [
      (
        s.text('1. Prepare the computer', '1. Připravte počítač'),
        s.text(
          'Use Ethernet, or Wi-Fi if the computer supports Wake on Wireless LAN (WoWLAN). Enable wake in its firmware and network adapter. Use the MAC address of the adapter that stays connected during sleep. Test from sleep first.',
          'Použijte Ethernet, nebo Wi-Fi s podporou Wake on Wireless LAN (WoWLAN). Povolte probouzení ve firmwaru a síťovém adaptéru. Použijte MAC adaptéru, který zůstane připojený během spánku. Nejprve testujte probuzení ze spánku.',
        ),
      ),
      (
        s.text(
          'Without a cable: Windows WoWLAN',
          'Bez kabelu: WoWLAN ve Windows',
        ),
        s.text(
          'In Device Manager, open your Wi-Fi adapter. Enable Wake on Magic Packet in Advanced and Allow this device to wake the computer in Power Management, where available. Check firmware support too.\n\nIn Terminal, list configurable wake devices:\npowercfg /devicequery wake_programmable\n\nCheck devices reporting wake from S3 sleep:\npowercfg /devicequery wake_from_S3_supported\n\nOpen Terminal as administrator and run the following, replacing ADAPTER NAME with the exact Wi-Fi name from the list:\npowercfg /deviceenablewake "ADAPTER NAME"\n\nConfirm that Wi-Fi appears here:\npowercfg /devicequery wake_armed\n\nOn The Waker, choose Computer connection → Wi-Fi (WoWLAN), enter the computer’s Wi-Fi MAC, save and start it. Keep The Waker on the same home LAN. First test from sleep. These checks report configuration and driver capabilities; only a real sleep/wake test proves the complete path. A missing option or failed enable can mean a driver, firmware, hardware or administrator-permission limitation.',
          'Ve Správci zařízení otevřete Wi-Fi adaptér. Na kartě Upřesnit povolte Wake on Magic Packet. Na kartě Řízení spotřeby povolte zařízení probouzet počítač, pokud je tato volba dostupná. Zkontrolujte také podporu ve firmwaru.\n\nV Terminálu vypište zařízení, u kterých lze probouzení nastavit:\npowercfg /devicequery wake_programmable\n\nZkontrolujte zařízení hlásící podporu probuzení ze spánku S3:\npowercfg /devicequery wake_from_S3_supported\n\nOtevřete Terminál jako správce a spusťte následující příkaz. ADAPTER NAME nahraďte přesným názvem Wi-Fi adaptéru z výpisu:\npowercfg /deviceenablewake "ADAPTER NAME"\n\nOvěřte, že je Wi-Fi v tomto seznamu:\npowercfg /devicequery wake_armed\n\nNa budiči vyberte Připojení počítače → Wi-Fi (WoWLAN), zadejte Wi-Fi MAC cílového PC, uložte nastavení a spusťte jej. Budič musí být ve stejné domácí síti. Nejprve testujte ze spánku. Výpisy potvrzují nastavení a schopnosti hlášené ovladačem; celou cestu prokáže až skutečné probuzení. Chybějící volba nebo neúspěšné povolení může znamenat omezení ovladače, firmwaru, hardwaru nebo oprávnění správce.',
        ),
      ),
      (
        s.text('2. Connect Tailscale', '2. Připojte Tailscale'),
        s.text(
          'Install the separate Tailscale app on the Waker and the device you use remotely. Sign both into the same tailnet and connect them. No router port forwarding is needed.',
          'Nainstalujte samostatnou aplikaci Tailscale na budič a zařízení pro vzdálené ovládání. Přihlaste je do stejné sítě Tailscale a připojte je. Přesměrování portů v routeru není potřeba.',
        ),
      ),
      (
        s.text('3. Set up The Waker', '3. Nastavte budič'),
        s.text(
          'Use a device that stays awake at home on the computer’s LAN. In Settings, choose The Waker and the target’s connection type: Ethernet, Wi-Fi (WoWLAN) or USB Ethernet. Enter that adapter’s MAC and use Detect network to fill empty addresses. Check the Waker’s Tailscale IPv4 (100.x.x.x), then save and start it.',
          'Použijte zařízení, které zůstane zapnuté doma v místní síti počítače. V nastavení vyberte Budič a připojení cílového PC: Ethernet, Wi-Fi (WoWLAN) nebo USB Ethernet. Zadejte MAC tohoto adaptéru a tlačítkem Zjistit síť doplňte prázdné adresy. Zkontrolujte Tailscale IPv4 budiče (100.x.x.x), uložte nastavení a spusťte jej.',
        ),
      ),
      (
        s.text('4. Pair the other device', '4. Spárujte druhé zařízení'),
        s.text(
          'On The Waker, open Pairing link / QR. On the other Android device, choose User, scan the QR, and save. On Windows or Linux, paste the copied pairing link and save. The QR and link contain the same secret; share them only with trusted devices.',
          'Na budiči otevřete Párovací odkaz / QR. Na druhém Androidu vyberte Uživatel, načtěte QR kód a uložte nastavení. Ve Windows nebo Linuxu vložte zkopírovaný párovací odkaz a uložte jej. QR kód i odkaz obsahují stejný tajný klíč. Sdílejte je jen s důvěryhodnými zařízeními.',
        ),
      ),
      (
        s.text('5. Wake', '5. Probuďte počítač'),
        s.text(
          'Keep Tailscale connected on both devices. Leave The Waker awake and on the home LAN, then press Wake on the User device. Packet sent confirms transmission, not that the computer started. A sleeping computer cannot be its own Waker.',
          'Nechte Tailscale připojený na obou zařízeních. Budič musí zůstat zapnutý v domácí síti. Na zařízení v režimu Uživatel stiskněte Probudit. Zpráva Paket odeslán potvrzuje přenos, ne spuštění počítače. Spící počítač nemůže být vlastním budičem.',
        ),
      ),
      (
        s.text('Wi-Fi and USB', 'Wi-Fi a USB'),
        s.text(
          'Wi-Fi wake requires WoWLAN support in the computer, firmware, and driver; use the Wi-Fi MAC. USB Ethernet works only with a powered, wake-capable USB network adapter. A charging cable between a phone and PC does not provide USB remote wake. A USB keyboard can wake a PC only if the device, firmware, and OS allow it. This app does not emulate a USB keyboard.',
          'Probuzení přes Wi-Fi vyžaduje podporu WoWLAN v počítači, firmwaru a ovladači. Použijte MAC Wi-Fi adaptéru. USB Ethernet vyžaduje napájený USB síťový adaptér s podporou probouzení. Nabíjecí kabel mezi telefonem a PC sám USB probouzení nezajistí. USB klávesnice může PC probudit, pokud to podporují zařízení, firmware a systém. Tato aplikace USB klávesnici neemuluje.',
        ),
      ),
      (
        s.text(
          'Laptop, desktop and Raspberry Pi',
          'Notebook, počítač a Raspberry Pi',
        ),
        s.text(
          'A second Windows or Linux computer can be The Waker. Keep it powered and awake on the target LAN, and leave Selia Wake open. Check laptop lid-close and sleep settings. For a Raspberry Pi, server or device without a desktop, download the standalone CLI from GitHub Releases. It supports User and Waker commands without Flutter, GTK or a keyring. Choose Linux ARM64 or ARMv7 to match the installed OS. It stores a plaintext secret in a file protected by OS permissions. Do not put that file in a shared or synced folder. CLI and GUI use separate settings. ESP32 boards need the companion firmware and a separate Tailscale gateway; a classic Arduino Uno cannot run the desktop app or Tailscale. Full terminal and device instructions:\nhttps://majkey25.github.io/selia-wake/terminal.html',
          'Druhý počítač s Windows nebo Linuxem může být budičem. Nechte jej napájený a zapnutý v místní síti cílového PC a aplikaci nezavírejte. Zkontrolujte uspávání při zavření víka notebooku. Pro Raspberry Pi, server nebo zařízení bez plochy stáhněte samostatné CLI z GitHub Releases. Podporuje příkazy uživatele i budiče bez Flutteru, GTK a klíčenky. Zvolte Linux ARM64 nebo ARMv7 podle nainstalovaného systému. Tajný klíč ukládá nešifrovaně do souboru chráněného oprávněními systému. Soubor nedávejte do sdílené nebo synchronizované složky. CLI a grafická aplikace mají oddělená nastavení. ESP32 potřebuje doprovodný firmware a samostatnou bránu Tailscale. Klasické Arduino Uno nespustí desktopovou aplikaci ani Tailscale. Úplný návod pro terminál a zařízení:\nhttps://majkey25.github.io/selia-wake/terminal.html',
        ),
      ),
      (
        s.text('Appearance', 'Vzhled'),
        s.text(
          'Settings offers the platform style, Material You, Terminal, Matrix and Custom. Custom lets you set colors, font, text size, corner radius and border width, with a preview before saving. System permission dialogs keep their OS appearance. The app uses Flutter-rendered standard controls; Windows uses Fluent controls. No decorative graphics or animations are required.',
          'V nastavení vyberte systémový styl, Material You, Terminal, Matrix nebo Vlastní. Vlastní vzhled umožňuje nastavit barvy, písmo, velikost textu, zaoblení a šířku okrajů s náhledem před uložením. Systémové dialogy oprávnění si ponechají vzhled systému. Aplikace používá standardní prvky vykreslené Flutterem. Windows používá prvky Fluent. Aplikace nepotřebuje dekorativní grafiku ani animace.',
        ),
      ),
      (
        s.text('If it does not work', 'Když probuzení nefunguje'),
        s.text(
          'Check the selected adapter’s connection, MAC, firmware and driver wake settings, and home network isolation. On Windows, check powercfg /lastwake after a test. Connect The Waker to the same LAN. With a Tailscale exit node, allow local LAN access. For a desktop Waker, allow only the intended Tailscale peers through its firewall on TCP 45879. On Android, allow background operation for both apps and power the Waker from a wall charger.',
          'Zkontrolujte připojení vybraného adaptéru, jeho MAC, probouzení ve firmwaru i ovladači a izolaci domácí sítě. Ve Windows po testu pomůže powercfg /lastwake. Budič musí být ve stejné místní síti. Při použití výstupního uzlu Tailscale povolte přístup do místní sítě. U budiče na počítači povolte ve firewallu TCP 45879 jen zamýšleným zařízením Tailscale. Na Androidu povolte běh obou aplikací na pozadí a napájejte budič ze síťové nabíječky.',
        ),
      ),
    ];
    return WakeScaffold(
      title: s.text('Setup guide', 'Návod k propojení'),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final (title, body) in steps) ...[
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(body),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
