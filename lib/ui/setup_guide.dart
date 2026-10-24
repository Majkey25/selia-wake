import 'package:flutter/material.dart';

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
          'Connect the computer to the router by Ethernet. Enable Wake-on-LAN in its firmware and network adapter. Use that adapter’s MAC address. Test from sleep first.',
          'Připojte počítač Ethernetem k routeru. Povolte Wake-on-LAN ve firmwaru a síťovém adaptéru. Použijte MAC tohoto adaptéru. Nejprve testujte probuzení ze spánku.',
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
          'Use a device that stays awake at home on the computer’s LAN. In Settings, choose The Waker, enter the computer’s MAC, and use Detect network to fill empty addresses. Check its Tailscale IPv4 (100.x.x.x), then save and start it.',
          'Použijte zařízení, které zůstane zapnuté doma v místní síti počítače. V nastavení vyberte Budič, zadejte MAC počítače a tlačítkem Zjistit síť doplňte prázdné adresy. Zkontrolujte Tailscale IPv4 budiče (100.x.x.x), uložte nastavení a spusťte jej.',
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
        s.text('If it does not work', 'Když probuzení nefunguje'),
        s.text(
          'Check the target’s Ethernet link, MAC, Wake-on-LAN settings, and home network isolation. Connect The Waker to the same LAN. With a Tailscale exit node, allow local LAN access. For a desktop Waker, allow only the intended Tailscale peers through its firewall on TCP 45879. On Android, allow background operation for both apps and power the Waker from a wall charger.',
          'Zkontrolujte ethernetové spojení cílového PC, MAC, povolené Wake-on-LAN a izolaci domácí sítě. Budič musí být ve stejné místní síti. Při použití výstupního uzlu Tailscale povolte přístup do místní sítě. U budiče na počítači povolte ve firewallu TCP 45879 jen zamýšleným zařízením Tailscale. Na Androidu povolte běh obou aplikací na pozadí a napájejte budič ze síťové nabíječky.',
        ),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.text('Setup guide', 'Návod k propojení'))),
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
                Text(body),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
