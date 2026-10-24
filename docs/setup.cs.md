# Propojení přes Tailscale

Potřebujete tři role: počítač, který má spát; zapnutý budič v jeho domácí síti; a zařízení, ze kterého jej ovládáte. Selia Wake stačí nainstalovat na poslední dvě zařízení. Spící počítač nemůže být vlastním budičem.

1. Zvolte Ethernet, nebo Wi-Fi s podporou WoWLAN. V BIOSu a ovladači zvoleného adaptéru povolte probouzení / Wake on Magic Packet. U některých desek ASUS se volba jmenuje Power On By PCI-E. Použijte MAC připojeného adaptéru. Nejprve zkoušejte probuzení ze spánku.
2. Na budič a vzdálené zařízení nainstalujte [Tailscale](https://tailscale.com/download). Přihlaste je do stejné sítě Tailscale a připojte je. Router nepotřebuje přesměrované porty. Pravidla vaší sítě Tailscale musí dovolit spojení mezi těmito zařízeními.
3. Na zařízení, které zůstane doma zapnuté, otevřete Selia Wake → Nastavení → Budič. Zadejte název a MAC cílového PC. Tlačítkem Zjistit síť doplňte prázdné adresy. Zkontrolujte místní broadcast a Tailscale IPv4 budiče, například `100.x.x.x`. Uložte a spusťte budič.
4. V nastavení budiče otevřete Párovací odkaz / QR. Na druhém Androidu vyberte režim Uživatel a Načíst QR kód. Povolte kameru, načtěte kód a zkontrolujte jméno a adresu budiče. Potvrďte Uložit nastavení. Ve Windows a Linuxu vložte párovací odkaz a uložte jej.
5. Nechte budič zapnutý v domácí síti a Tailscale připojený na obou zařízeních. Na vzdáleném zařízení stiskněte Probudit. „Paket odeslán“ potvrzuje odeslání, nikoli skutečný start počítače.

QR kód i odkaz obsahují stejný tajný klíč. Odkaz neotevírá webovou stránku ani sám nevytvoří spojení Tailscale; přenese adresu budiče a klíč do druhé instalace aplikace. Neukládejte jej veřejně. Odstranění párování na jednom zařízení neodvolá ostatní kopie klíče. Aplikace zatím nemá tlačítko pro jeho výměnu; na Androidu nový klíč vznikne po vymazání dat aplikace budiče, což odstraní i jeho nastavení a vyžaduje nové párování všech zařízení.

## Wi-Fi a USB

- **Ethernet:** doporučený začátek. Kabel cílového počítače musí být skutečně připojený. Budič může být na domácí Wi-Fi, pokud síť neizoluje Wi-Fi od kabelových zařízení.
- **Wi-Fi / WoWLAN:** potřebujete podporu v adaptéru, firmwaru i ovladači cílového PC. Použijte jeho Wi-Fi MAC. Samotná změna volby v aplikaci podporu nepřidá.
- **USB Ethernet:** potřebujete USB síťový adaptér, který podporuje probouzení a zůstane během spánku napájený. Použijte MAC tohoto adaptéru a připojte jej k LAN.

Obyčejný USB kabel mezi telefonem a PC počítač touto aplikací neprobudí. USB probouzení klávesnicí funguje jen s podporovaným zařízením, firmwarem a systémovým ovladačem. Selia Wake telefon na USB klávesnici nepřemění.

### Bez kabelu: WoWLAN ve Windows

Ve Správci zařízení otevřete Wi-Fi adaptér. Na kartě Upřesnit povolte Wake on Magic Packet. Na kartě Řízení spotřeby povolte zařízení probouzet počítač, pokud tuto volbu ovladač nabízí. Zkontrolujte také podporu ve firmwaru.

V Terminálu vypište nastavitelné adaptéry a podporu probuzení ze spánku S3:

```powershell
powercfg /devicequery wake_programmable
powercfg /devicequery wake_from_S3_supported
```

Otevřete Terminál **jako správce**. V tomto příkazu nahraďte `ADAPTER NAME` přesným názvem Wi-Fi adaptéru z výpisu:

```powershell
powercfg /deviceenablewake "ADAPTER NAME"
```

Ověřte, že se Wi-Fi objevuje mezi povolenými zařízeními:

```powershell
powercfg /devicequery wake_armed
```

Na budiči nastavte Připojení počítače → Wi-Fi (WoWLAN) a Wi-Fi MAC cílového PC. Uložte nastavení a spusťte budič. Nechte jej ve stejné domácí síti. První test proveďte ze spánku. Samotný seznam potvrzuje nastavení, nikoli skutečné probuzení. Chybějící volby mohou znamenat omezení ovladače, hardwaru nebo firmwaru. Chyba oprávnění vyžaduje Terminál spuštěný jako správce.

## Když to nefunguje

Zkontrolujte připojení zvoleného adaptéru, jeho MAC, BIOS a Wake on Magic Packet. Ve Windows pomůže `powercfg /devicequery wake_armed`: ukazuje zařízení povolená k probouzení. Po testu vypíše `powercfg /lastwake` poslední zdroj probuzení. Výpisy samy neprokazují funkčnost celé cesty.

Budič musí být ve stejné místní síti jako cílový PC. Nepoužívejte izolovanou síť pro hosty. Při výstupním uzlu Tailscale povolte přístup do místní sítě. U budiče ve Windows/Linuxu povolte TCP 45879 pouze zamýšleným zařízením Tailscale; port neotevírejte veřejnému internetu.

Na Androidu povolte běh Selia Wake i Tailscale na pozadí. Budič má trvalé oznámení a tlačítko Zastavit. Napájejte jej ze síťové nabíječky, aby zůstal zapnutý i při vypnutí cílového PC. Po restartu zařízení musíte budič znovu spustit. Na počítači běží pouze po dobu otevření aplikace.

Podklady: [Tailscale a Wake-on-LAN](https://tailscale.com/blog/wake-on-lan-tailscale-upsnap), [ASUS Wake-on-LAN](https://www.asus.com/support/faq/1045950/), [Microsoft USB remote wake](https://learn.microsoft.com/en-us/windows-hardware/drivers/usbcon/remote-wakeup-of-usb-devices).
