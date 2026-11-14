"""scripts/netinfo.sh: the Wi-Fi panel's connection details (address, gateway, DNS, band,
speed, security, channel, VPN), from NetworkManager's nmcli (stubbed with fixture output)."""
import slate
from slate import Case, run
from stubs import Stubs, fixture_text

SCRIPT = slate.path("shell", "scripts", "netinfo.sh")


class NetInfo(Case):
    scratch = True

    def setUp(self):
        super().setUp()
        self.s = Stubs(self.h)

    def nmcli(self, devices="devices.txt", connections=""):
        f = lambda n: fixture_text("netinfo", n) if n else ""
        self.s.add("nmcli", by_args={
            "DEVICE,TYPE,STATE": f(devices), "IP4.ADDRESS": f("device-show.txt"),
            "IN-USE": f("wifi-list.txt"), "TYPE,NAME": f(connections)})

    def info(self):
        code, out = run(["sh", SCRIPT], env=self.s.env)
        self.assertEqual(code, 0, out)
        return out

    WIFI = ("ip=192.0.2.23/24\ngateway=192.0.2.1\ndns=192.0.2.53\n"
            "freq=5180 MHz\nrate=540 Mbit/s\nsecurity=WPA2 WPA3\nchannel=36\n")

    def test_connected(self):
        """The first address and DNS server, and the network in use (not the others in range)."""
        self.nmcli()
        self.assertEqual(self.info(), self.WIFI)

    def test_asks_about_the_wifi_device(self):
        self.nmcli()
        self.info()
        calls = self.s.calls("nmcli")
        self.assertIn(["-t", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show", "wlp2s0"], calls)
        self.assertIn(["-t", "-f", "IN-USE,FREQ,RATE,SECURITY,CHAN", "device", "wifi", "list",
                       "ifname", "wlp2s0", "--rescan", "no"], calls)
        # Devices are asked for once, for both the Wi-Fi device and the tunnels
        self.assertEqual(sum(1 for c in calls if "DEVICE,TYPE,STATE" in c), 1)

    def test_not_connected(self):
        """No Wi-Fi connection: nothing at all, and nothing more asked."""
        self.nmcli(devices="devices-offline.txt")
        self.assertEqual(self.info(), "")
        self.assertEqual(len(self.s.calls("nmcli")), 1)

    def test_no_networkmanager(self):
        self.s.add("nmcli", missing=True)
        self.assertEqual(self.info(), "")

    def test_nmcli_fails(self):
        self.s.add("nmcli", stdout="", code=8)
        self.assertEqual(self.info(), "")

    def test_vpn_connection(self):
        """A NetworkManager VPN by its connection name, before tunnel devices."""
        self.nmcli(devices="devices-vpn.txt", connections="connections-vpn.txt")
        self.assertEqual(self.info(), self.WIFI + "vpn=Office VPN\n")

    def test_vpn_name_with_a_colon(self):
        """A colon in the connection's name: the whole name, where the VPN used to go unseen.
        (The replies are nmcli's own: it escapes a colon in a value unless told "-e no".)"""
        self.s.add("nmcli", by_args={
            "DEVICE,TYPE,STATE": fixture_text("netinfo", "devices.txt"),
            "IP4.ADDRESS": fixture_text("netinfo", "device-show.txt"),
            "IN-USE": fixture_text("netinfo", "wifi-list.txt"),
            "-e no -f TYPE,NAME": "802-11-wireless:Home Wi-Fi\nvpn:Office: London\n",
            "TYPE,NAME": "802-11-wireless:Home Wi-Fi\nvpn:Office\\: London\n",
            "NAME,TYPE": "Home Wi-Fi:802-11-wireless\nOffice\\: London:vpn\n"})
        self.assertEqual(self.info(), self.WIFI + "vpn=Office: London\n")

    def test_tunnel_from_another_app(self):
        """A tunnel NetworkManager doesn't manage (e.g. a VPN app's own), by its device."""
        self.nmcli(devices="devices-vpn.txt")
        self.assertEqual(self.info(), self.WIFI + "vpn=tun0\n")

    def test_vpn_pick_is_the_first_of_all_the_names(self):
        """Connection names and tunnel devices together, sorted, the first one: the same
        answer however many programs it takes to find it."""
        self.nmcli(devices="devices-vpn.txt", connections="connections-vpn.txt")
        # (fixtures: the VPN "Office VPN", the WireGuard "wg0", the tunnels wg0 and tun0)
        self.assertEqual(self.info(), self.WIFI + "vpn=Office VPN\n")

    def test_few_programs_for_every_reading(self):
        """It runs every few seconds while the panel's open, so it reads the lists in the shell
        itself: no head, no cut, and awk only for the Wi-Fi's own line."""
        self.nmcli(devices="devices-vpn.txt", connections="connections-vpn.txt")
        for tool in ("head", "cut", "awk", "grep"):
            self.s.add(tool, stdout="")
        self.info()
        self.assertEqual(self.s.calls("head"), [])
        self.assertEqual(self.s.calls("cut"), [])
        self.assertEqual(self.s.calls("grep"), [])
        self.assertLessEqual(len(self.s.calls("awk")), 1)

    def test_no_vpn(self):
        """Only the Wi-Fi connection active: no vpn line."""
        self.s.add("nmcli", by_args={
            "DEVICE,TYPE,STATE": fixture_text("netinfo", "devices.txt"),
            "IP4.ADDRESS": fixture_text("netinfo", "device-show.txt"),
            "IN-USE": fixture_text("netinfo", "wifi-list.txt"),
            "TYPE,NAME": "802-11-wireless:Home Wi-Fi\nloopback:lo\n"})
        self.assertNotIn("vpn=", self.info())

    def test_network_not_in_list(self):
        """The scan list without the network in use (it's being rescanned): just the addresses."""
        self.s.add("nmcli", by_args={
            "DEVICE,TYPE,STATE": fixture_text("netinfo", "devices.txt"),
            "IP4.ADDRESS": fixture_text("netinfo", "device-show.txt"),
            "IN-USE": " :2437 MHz:130 Mbit/s:WPA2:6\n"})
        self.assertEqual(self.info(), "ip=192.0.2.23/24\ngateway=192.0.2.1\ndns=192.0.2.53\n")

    def test_open_network(self):
        """No security: an empty value, not a missing line."""
        self.s.add("nmcli", by_args={
            "DEVICE,TYPE,STATE": fixture_text("netinfo", "devices.txt"),
            "IP4.ADDRESS": "IP4.ADDRESS[1]:192.0.2.23/24\nIP4.GATEWAY:\n",
            "IN-USE": "*:2412 MHz:65 Mbit/s::1\n"})
        self.assertEqual(self.info(), "ip=192.0.2.23/24\ngateway=\nfreq=2412 MHz\nrate=65 Mbit/s\nsecurity=\nchannel=1\n")
