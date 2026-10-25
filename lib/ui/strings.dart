import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/protocol.dart';
import '../core/settings.dart';

class Strings {
  const Strings(this.czech);
  final bool czech;

  static Strings of(BuildContext context) =>
      Strings(Localizations.localeOf(context).languageCode == 'cs');

  String text(String english, String czech) => this.czech ? czech : english;
  String get settings => text('Settings', 'Nastavení');
  String get saveSettings => text('Save settings', 'Uložit nastavení');
  String get revertChanges => text('Revert changes', 'Vrátit změny');
  String get resetDefaults => text('Reset defaults', 'Obnovit výchozí');
  String get autoSaveHelp => text(
    'Changes apply automatically. Revert restores settings from when you opened this page.',
    'Změny se ukládají automaticky. Vrátit změny obnoví nastavení při otevření této stránky.',
  );
  String get savingChanges => text('Saving changes…', 'Ukládání změn…');
  String get invalidChanges => text(
    'Changes not saved. Correct the marked fields.',
    'Změny nebyly uloženy. Opravte označená pole.',
  );
  String get resetDefaultsHelp => text(
    'Restores default appearance and disconnects paired devices. Target and network settings are cleared. Revert can undo this while this page is open.',
    'Obnoví výchozí vzhled a odpojí spárovaná zařízení. Smaže nastavení cíle a sítě. Dokud je tato stránka otevřená, lze reset vrátit.',
  );
  String get appearance => text('Appearance', 'Vzhled');
  String themeName(WakeTheme theme) => switch (theme) {
    WakeTheme.platform => platformTheme,
    WakeTheme.material => 'Material You',
    WakeTheme.matrix => 'Matrix',
    WakeTheme.terminal => 'Terminal',
    WakeTheme.custom => text('Custom', 'Vlastní'),
  };
  String get platformTheme => switch (defaultTargetPlatform) {
    TargetPlatform.windows => text('Platform (Fluent)', 'Platforma (Fluent)'),
    TargetPlatform.linux => text(
      'Platform (GTK style)',
      'Platforma (styl GTK)',
    ),
    _ => text('Platform (Material You)', 'Platforma (Material You)'),
  };
  String get platformStyleHelp => text(
    'Tap a preview to apply the theme.',
    'Klepnutím na náhled použijete motiv.',
  );
  String get retry => text('Retry', 'Zkusit znovu');
  String get user => text('User', 'Uživatel');
  String get waker => text('The Waker', 'Budič');
  String get sleeper => text('The Sleeper', 'Spáč');
  String get sleeperHelp => text(
    'Configure this PC to receive wake packets. A separate Waker must stay awake on the same LAN. This mode does not keep this PC awake.',
    'Nastavte tento počítač pro příjem probouzecích paketů. Samostatný budič musí zůstat zapnutý ve stejné místní síti. Tento režim neudržuje počítač vzhůru.',
  );
  String get networkDetails => text(
    'This setup contains the computer name, MAC and network addresses. Share it only with your trusted Waker. It contains no secret key.',
    'Nastavení obsahuje název počítače, MAC a síťové adresy. Sdílejte je pouze se svým důvěryhodným budičem. Neobsahuje tajný klíč.',
  );
  String get targetSetup => text('Sleeper setup', 'Nastavení spáče');
  String get invalidSetup => text(
    'Invalid Sleeper setup. Export a new target link from the Sleeper.',
    'Neplatné nastavení spáče. Na spáči vytvořte nový odkaz počítače.',
  );
  String get wake => text('Wake', 'Probudit');
  String get start => text('Start Waker', 'Spustit budič');
  String get stop => text('Stop Waker', 'Zastavit budič');
  String get name => text('Computer name', 'Název počítače');
  String get computer => text('My computer', 'Můj počítač');
  String get pairing => text('Pairing link', 'Párovací odkaz');
  String get sent => text(
    'Packet sent. Boot not confirmed.',
    'Paket odeslán. Spuštění počítače není potvrzeno.',
  );
  String get statusError => text(
    'Cannot check Waker status. Retry before changing the relay.',
    'Stav budiče nelze zjistit. Před změnou relé to zkuste znovu.',
  );
  String get macError => text(
    'Enter a valid unicast MAC, such as 00:11:22:33:44:55.',
    'Zadejte platnou unicast MAC, například 00:11:22:33:44:55.',
  );
  String get broadcastError => text(
    'Enter a LAN broadcast IPv4, or leave it empty for automatic selection.',
    'Zadejte broadcast IPv4 místní sítě, nebo nechte pole prázdné pro automatickou volbu.',
  );
  String get lanError => text(
    'Enter this Waker’s physical LAN IPv4, such as 192.168.1.20.',
    'Zadejte IPv4 tohoto budiče v místní síti, například 192.168.1.20.',
  );
  String get hostError => text(
    'Enter the Waker’s Tailscale IPv4 in 100.64.0.0/10.',
    'Zadejte Tailscale IPv4 budiče v rozsahu 100.64.0.0/10.',
  );
  String get saveError => text(
    'Settings could not be saved. Check storage access and retry. The Waker may be stopped.',
    'Nastavení se nepodařilo uložit. Zkontrolujte přístup k úložišti a zkuste to znovu. Budič může být zastavený.',
  );
  String get localHelp => text(
    'Keep this device awake on the computer’s LAN. Enable Wake-on-LAN on the computer.',
    'Nechte toto zařízení zapnuté v místní síti počítače. Na počítači povolte Wake-on-LAN.',
  );
  String get tailscaleHelp => text(
    'Install and connect Tailscale on both devices. Without a Tailscale IPv4, the local Waker can start, but you cannot export remote pairing.',
    'Nainstalujte a připojte Tailscale na obou zařízeních. Bez Tailscale IPv4 lze místní budič spustit, ale párování pro vzdálené ovládání nelze sdílet.',
  );

  String failure(Object error) {
    final code = switch (error) {
      ProtocolFailure(:final code) => code,
      PlatformException(:final code) => code,
      FormatException(:final message) => message,
      _ => '',
    };
    return switch (code) {
      'invalid_target' => text(
        'Check the computer’s private or Tailscale IPv4 and TCP port in Settings.',
        'Zkontrolujte soukromou nebo Tailscale IPv4 a TCP port počítače v nastavení.',
      ),
      'invalid_mac' => macError,
      'invalid_lan' => lanError,
      'invalid_broadcast' => broadcastError,
      'invalid_key' || 'invalid_pairing' => text(
        'Invalid pairing link. Copy a new link from the Waker’s settings.',
        'Neplatný párovací odkaz. Zkopírujte nový odkaz z nastavení budiče.',
      ),
      'unauthorized' => text(
        'Pairing was rejected. Import a current link from the Waker.',
        'Párování bylo odmítnuto. Načtěte aktuální odkaz z budiče.',
      ),
      'expired' || 'replay' => text(
        'Check automatic date and time on both devices, then retry.',
        'Zkontrolujte automatické datum a čas na obou zařízeních a zkuste to znovu.',
      ),
      'rate_limited' => text(
        'Too many requests. Wait a minute and retry.',
        'Příliš mnoho požadavků. Počkejte minutu a zkuste to znovu.',
      ),
      'wifi_unavailable' => text(
        'Connect the Waker to the computer’s Wi-Fi network and retry.',
        'Připojte budič k Wi-Fi síti počítače a zkuste to znovu.',
      ),
      'scanner_failed' || 'camera_permission_denied' => text(
        'The camera could not be opened. Allow camera access or paste a pairing link.',
        'Kameru se nepodařilo otevřít. Povolte přístup ke kameře nebo vložte párovací odkaz.',
      ),
      'send_failed' => text(
        'The LAN packet could not be sent. Check the Waker’s LAN connection and broadcast address.',
        'Paket do místní sítě se nepodařilo odeslat. Zkontrolujte připojení budiče a broadcast adresu.',
      ),
      'invalid_response' || 'invalid_request' => text(
        'The Waker returned an invalid response. Check that both devices use the same app version.',
        'Budič vrátil neplatnou odpověď. Zkontrolujte, že obě zařízení používají stejnou verzi aplikace.',
      ),
      _ =>
        error is SocketException || error is TimeoutException
            ? text(
                'Cannot reach the Waker. Check Tailscale on both devices, the Waker status, and the firewall.',
                'Budič není dostupný. Zkontrolujte Tailscale na obou zařízeních, stav budiče a firewall.',
              )
            : text(
                'The operation failed. Check the Waker’s network, permissions, and whether another relay uses port $relayPort. Retry.',
                'Operace selhala. Zkontrolujte síť a oprávnění budiče a zda jiné relé nepoužívá port $relayPort. Zkuste to znovu.',
              ),
    };
  }
}
