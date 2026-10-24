import 'package:flutter/material.dart';

import 'controls.dart';
import 'strings.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final sections = [
      (
        s.text('Developer and contact', 'Vývojář a kontakt'),
        s.text(
          'Effective 24 October 2026. Selia Wake is maintained by Matěj Teplý, publishing as Majkey / MajkeyLab. Privacy and support: majkeylab@gmail.com. Do not send pairing secrets or screenshots of pairing QR codes.',
          'Platí od 24. října 2026. Selia Wake spravuje Matěj Teplý pod označením Majkey / MajkeyLab. Soukromí a podpora: majkeylab@gmail.com. Neposílejte tajné párovací odkazy ani snímky párovacích QR kódů.',
        ),
      ),
      (
        s.text('Local data', 'Místní data'),
        s.text(
          'Device names, network addresses, target MAC, settings and pairing keys stay in OS secure storage on your devices until you remove them. The app has no developer-operated server, app accounts, advertising, analytics or tracking SDK. It does not sell data. Camera images are decoded locally with ZXing only when you start QR scanning; they are not saved or uploaded. Clipboard access happens only after Copy or Paste.',
          'Názvy zařízení, síťové adresy, cílová MAC, nastavení a párovací klíče zůstávají v zabezpečeném úložišti systému na vašich zařízeních, dokud je neodstraníte. Aplikace nemá server provozovaný vývojářem, vlastní účty, reklamu, analytiku ani sledovací SDK. Data neprodává. Obraz kamery dekóduje místně pomocí ZXing jen po spuštění QR skeneru; snímky neukládá ani nenahrává. Schránku používá pouze po stisknutí Kopírovat nebo Vložit.',
        ),
      ),
      (
        s.text('Communication and permissions', 'Komunikace a oprávnění'),
        s.text(
          'Wake sends a timestamp, random nonce and HMAC signature to your paired Waker. The Waker broadcasts the target MAC on your LAN. Pairing links and QR codes transfer the Waker address, name and secret to devices you choose. Tailscale is a separate app and service that encrypts remote transport under its own privacy policy; Selia Wake does not receive its account credentials. Network/Wi-Fi permissions enable the relay, camera permission enables explicit QR scanning, and notifications plus a wake lock support the visible Android Waker service. A bounded in-memory replay cache rejects nonce reuse for at least 60 seconds and through the request timestamp\'s final accepted second. Expired entries are pruned when processing new requests. Android app backup is disabled.',
          'Probudit odešle čas, náhodný nonce a podpis HMAC spárovanému budiči. Budič vyšle cílovou MAC do místní sítě. Párovací odkaz a QR kód předají adresu, název a tajný klíč budiče vámi zvolenému zařízení. Tailscale je samostatná aplikace a služba, která šifruje vzdálený přenos podle vlastních zásad soukromí; Selia Wake nedostává její přihlašovací údaje. Síťová a Wi-Fi oprávnění umožňují provoz budiče, kamera slouží k výslovně spuštěnému skenování QR a oznámení se zámkem bdění podporují viditelnou službu budiče na Androidu. Omezená paměť ochrany proti opakování odmítá opakovaný nonce alespoň 60 sekund a až do konce časové platnosti požadavku. Prošlé položky se odstraní při zpracování dalších požadavků. Zálohování dat aplikace na Androidu je vypnuté.',
        ),
      ),
      (
        s.text('Removal and retention', 'Odstranění a uchovávání'),
        s.text(
          'Stop The Waker to stop relaying. To remove a User pairing, choose Forget pairing and Save settings. This does not revoke keys copied elsewhere. On Android, clearing app storage or uninstalling removes private app data; clearing a Waker’s data requires new setup and pairing. Desktop secure-storage data can remain after deleting the portable app. See the website’s data-removal instructions. There is no Selia Wake account or server-side app data to delete. Tailscale accounts are managed separately with Tailscale. Support correspondence is handled by email providers and kept as needed to answer requests and meet legal obligations; email the contact above to request its removal.',
          'Zastavením budiče ukončíte předávání požadavků. Párování uživatele odeberete volbou Zapomenout párování a Uložit nastavení. Tím neodvoláte klíče zkopírované jinam. Na Androidu odstraní soukromá data vymazání úložiště aplikace nebo odinstalace; po vymazání dat budiče je nutné nové nastavení a párování. Na počítači mohou data zabezpečeného úložiště zůstat i po smazání přenosné aplikace. Postup odstranění najdete na webu. Účet Selia Wake ani data aplikace na serveru neexistují. Účty Tailscale spravuje samostatně Tailscale. Korespondenci podpory zpracovávají poskytovatelé e-mailu a uchovává se po dobu potřebnou k vyřízení požadavků a splnění zákonných povinností; o její odstranění požádejte na uvedeném kontaktu.',
        ),
      ),
      (
        s.text('CLI and companion devices', 'CLI a doprovodná zařízení'),
        s.text(
          'The separate CLI stores configuration and pairing keys in a plaintext local file with owner-only file permissions or Windows access rules. It does not use the GUI secure store. Protect backups and synced copies. ESP32 firmware stores Wi-Fi credentials and the pairing key in its nonvolatile memory, without a promise of encrypted flash. Remove configuration before transferring a device. See the full website policy for these separate installations.',
          'Samostatné CLI ukládá nastavení a párovací klíče nešifrovaně do místního souboru chráněného oprávněními vlastníka nebo přístupovými pravidly Windows. Nepoužívá zabezpečené úložiště grafické aplikace. Chraňte zálohy a synchronizované kopie. Firmware ESP32 ukládá přístupové údaje Wi-Fi a párovací klíč do trvalé paměti, bez záruky šifrování flash. Před předáním zařízení odstraňte nastavení. Tyto samostatné instalace popisují úplné zásady na webu.',
        ),
      ),
      (
        s.text('Website and further information', 'Web a další informace'),
        s.text(
          'The website has no app-added cookies, analytics or external fonts. GitHub Pages logs visitors’ IP addresses for security under GitHub’s privacy statement. Opening external services is subject to their policies. Full website policy and support:\nhttps://majkey25.github.io/selia-wake/privacy.html\nhttps://majkey25.github.io/selia-wake/support.html\nhttps://tailscale.com/privacy-policy',
          'Web nepřidává cookies, analytiku ani externí fonty. GitHub Pages zaznamenává IP adresy návštěvníků pro zabezpečení podle zásad GitHubu. Externí služby mají vlastní pravidla. Úplné zásady webu a podpora:\nhttps://majkey25.github.io/selia-wake/privacy.html\nhttps://majkey25.github.io/selia-wake/support.html\nhttps://tailscale.com/privacy-policy',
        ),
      ),
    ];
    return WakeScaffold(
      title: s.text('Privacy & support', 'Soukromí a podpora'),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final (title, body) in sections) ...[
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
