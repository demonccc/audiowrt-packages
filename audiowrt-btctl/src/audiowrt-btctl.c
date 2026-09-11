// SPDX-License-Identifier: GPL-2.0-only
#include <gio/gio.h>
#include <glib.h>
#include <stdio.h>
#include <string.h>

#define BLUEZ_BUS "org.bluez"
#define ROOT_PATH "/"
#define AGENT_PATH "/org/audiowrt/agent"

static GDBusConnection *bus;
static GMainLoop *pair_loop;
static gboolean pair_ok;

static GVariant *managed_objects(GError **error) {
	GVariant *reply = g_dbus_connection_call_sync(bus, BLUEZ_BUS, ROOT_PATH,
		"org.freedesktop.DBus.ObjectManager", "GetManagedObjects", NULL,
		G_VARIANT_TYPE("(a{oa{sa{sv}}})"), G_DBUS_CALL_FLAGS_NONE, 10000, NULL, error);
	if (!reply) return NULL;
	GVariant *objects = NULL;
	g_variant_get(reply, "(@a{oa{sa{sv}}})", &objects);
	g_variant_unref(reply);
	return objects;
}

static GVariant *find_interface(GVariant *interfaces, const char *wanted) {
	GVariantIter iter;
	const gchar *name;
	GVariant *props;
	g_variant_iter_init(&iter, interfaces);
	while (g_variant_iter_next(&iter, "{&s@a{sv}}", &name, &props)) {
		if (strcmp(name, wanted) == 0) return props;
		g_variant_unref(props);
	}
	return NULL;
}

static gchar *find_adapter(void) {
	GError *error = NULL;
	GVariant *objects = managed_objects(&error);
	if (!objects) {
		g_printerr("ERROR: %s\n", error ? error->message : "cannot query BlueZ");
		g_clear_error(&error);
		return NULL;
	}
	GVariantIter iter;
	const gchar *path;
	GVariant *interfaces;
	gchar *result = NULL;
	g_variant_iter_init(&iter, objects);
	while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
		GVariant *props = find_interface(interfaces, "org.bluez.Adapter1");
		if (props) {
			result = g_strdup(path);
			g_variant_unref(props);
			g_variant_unref(interfaces);
			break;
		}
		g_variant_unref(interfaces);
	}
	g_variant_unref(objects);
	return result;
}

static gchar *find_device(const char *mac) {
	GError *error = NULL;
	GVariant *objects = managed_objects(&error);
	if (!objects) { g_clear_error(&error); return NULL; }
	GVariantIter iter;
	const gchar *path;
	GVariant *interfaces;
	gchar *result = NULL;
	g_variant_iter_init(&iter, objects);
	while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
		GVariant *props = find_interface(interfaces, "org.bluez.Device1");
		if (props) {
			const gchar *address = NULL;
			if (g_variant_lookup(props, "Address", "&s", &address) && address && g_ascii_strcasecmp(address, mac) == 0)
				result = g_strdup(path);
			g_variant_unref(props);
		}
		g_variant_unref(interfaces);
		if (result) break;
	}
	g_variant_unref(objects);
	return result;
}

static gboolean set_property(const char *path, const char *interface, const char *property, GVariant *value) {
	GError *error = NULL;
	GVariant *reply = g_dbus_connection_call_sync(bus, BLUEZ_BUS, path,
		"org.freedesktop.DBus.Properties", "Set",
		g_variant_new("(ssv)", interface, property, value), NULL,
		G_DBUS_CALL_FLAGS_NONE, 10000, NULL, &error);
	if (!reply) {
		g_printerr("ERROR: %s\n", error ? error->message : "D-Bus property update failed");
		g_clear_error(&error);
		return FALSE;
	}
	g_variant_unref(reply);
	return TRUE;
}

static gboolean call_device(const char *path, const char *method, int timeout_ms) {
	GError *error = NULL;
	GVariant *reply = g_dbus_connection_call_sync(bus, BLUEZ_BUS, path,
		"org.bluez.Device1", method, NULL, NULL,
		G_DBUS_CALL_FLAGS_NONE, timeout_ms, NULL, &error);
	if (!reply) {
		g_printerr("ERROR: %s\n", error ? error->message : "BlueZ device operation failed");
		g_clear_error(&error);
		return FALSE;
	}
	g_variant_unref(reply);
	return TRUE;
}

static gboolean power_on(void) {
	gchar *adapter = find_adapter();
	if (!adapter) { g_printerr("ERROR: no Bluetooth adapter found.\n"); return FALSE; }
	gboolean ok = set_property(adapter, "org.bluez.Adapter1", "Powered", g_variant_new_boolean(TRUE));
	g_free(adapter);
	return ok;
}

static void print_devices(void) {
	GError *error = NULL;
	GVariant *objects = managed_objects(&error);
	if (!objects) {
		g_printerr("ERROR: %s\n", error ? error->message : "cannot query BlueZ");
		g_clear_error(&error);
		return;
	}
	GVariantIter iter;
	const gchar *path;
	GVariant *interfaces;
	g_variant_iter_init(&iter, objects);
	while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
		GVariant *props = find_interface(interfaces, "org.bluez.Device1");
		if (props) {
			const gchar *address = NULL, *alias = NULL;
			gboolean paired = FALSE, connected = FALSE;
			g_variant_lookup(props, "Address", "&s", &address);
			g_variant_lookup(props, "Alias", "&s", &alias);
			g_variant_lookup(props, "Paired", "b", &paired);
			g_variant_lookup(props, "Connected", "b", &connected);
			if (address) {
				gchar *safe = g_strdup(alias ? alias : address);
				for (gchar *p = safe; *p; p++) if (*p == '|' || *p == '\n' || *p == '\r') *p = ' ';
				g_print("%s|%s|%d|%d\n", address, safe, paired ? 1 : 0, connected ? 1 : 0);
				g_free(safe);
			}
			g_variant_unref(props);
		}
		g_variant_unref(interfaces);
	}
	g_variant_unref(objects);
}

static int scan_for(int seconds) {
	gchar *adapter = find_adapter();
	if (!adapter) { g_printerr("ERROR: no Bluetooth adapter found.\n"); return 2; }
	GError *error = NULL;
	GVariant *reply = g_dbus_connection_call_sync(bus, BLUEZ_BUS, adapter,
		"org.bluez.Adapter1", "StartDiscovery", NULL, NULL,
		G_DBUS_CALL_FLAGS_NONE, 10000, NULL, &error);
	if (!reply) {
		g_printerr("ERROR: %s\n", error ? error->message : "could not start discovery");
		g_clear_error(&error); g_free(adapter); return 3;
	}
	g_variant_unref(reply);
	g_usleep((gulong)seconds * G_USEC_PER_SEC);
	reply = g_dbus_connection_call_sync(bus, BLUEZ_BUS, adapter,
		"org.bluez.Adapter1", "StopDiscovery", NULL, NULL,
		G_DBUS_CALL_FLAGS_NONE, 10000, NULL, NULL);
	if (reply) g_variant_unref(reply);
	g_free(adapter);
	print_devices();
	return 0;
}

static const gchar agent_xml[] =
	"<node><interface name='org.bluez.Agent1'>"
	"<method name='Release'/><method name='Cancel'/>"
	"<method name='RequestPinCode'><arg type='o' direction='in'/><arg type='s' direction='out'/></method>"
	"<method name='DisplayPinCode'><arg type='o' direction='in'/><arg type='s' direction='in'/></method>"
	"<method name='RequestPasskey'><arg type='o' direction='in'/><arg type='u' direction='out'/></method>"
	"<method name='DisplayPasskey'><arg type='o' direction='in'/><arg type='u' direction='in'/><arg type='q' direction='in'/></method>"
	"<method name='RequestConfirmation'><arg type='o' direction='in'/><arg type='u' direction='in'/></method>"
	"<method name='RequestAuthorization'><arg type='o' direction='in'/></method>"
	"<method name='AuthorizeService'><arg type='o' direction='in'/><arg type='s' direction='in'/></method>"
	"</interface></node>";

static void agent_call(GDBusConnection *connection, const gchar *sender, const gchar *object_path,
	const gchar *interface_name, const gchar *method_name, GVariant *parameters,
	GDBusMethodInvocation *invocation, gpointer user_data) {
	(void)connection; (void)sender; (void)object_path; (void)interface_name; (void)parameters; (void)user_data;
	if (strcmp(method_name, "RequestPinCode") == 0)
		g_dbus_method_invocation_return_value(invocation, g_variant_new("(s)", "0000"));
	else if (strcmp(method_name, "RequestPasskey") == 0)
		g_dbus_method_invocation_return_value(invocation, g_variant_new("(u)", 0u));
	else
		g_dbus_method_invocation_return_value(invocation, NULL);
}

static const GDBusInterfaceVTable agent_vtable = { .method_call = agent_call };

static guint register_agent(GDBusNodeInfo **info_out) {
	GError *error = NULL;
	GDBusNodeInfo *info = g_dbus_node_info_new_for_xml(agent_xml, &error);
	if (!info) { g_printerr("ERROR: %s\n", error->message); g_clear_error(&error); return 0; }
	guint id = g_dbus_connection_register_object(bus, AGENT_PATH, info->interfaces[0], &agent_vtable, NULL, NULL, &error);
	if (!id) { g_printerr("ERROR: %s\n", error->message); g_clear_error(&error); g_dbus_node_info_unref(info); return 0; }
	GVariant *reply = g_dbus_connection_call_sync(bus, BLUEZ_BUS, "/org/bluez", "org.bluez.AgentManager1",
		"RegisterAgent", g_variant_new("(os)", AGENT_PATH, "NoInputNoOutput"), NULL,
		G_DBUS_CALL_FLAGS_NONE, 10000, NULL, &error);
	if (!reply) {
		g_printerr("ERROR: %s\n", error ? error->message : "could not register pairing agent");
		g_clear_error(&error); g_dbus_connection_unregister_object(bus, id); g_dbus_node_info_unref(info); return 0;
	}
	g_variant_unref(reply);
	*info_out = info;
	return id;
}

static void unregister_agent(guint id, GDBusNodeInfo *info) {
	GVariant *reply = g_dbus_connection_call_sync(bus, BLUEZ_BUS, "/org/bluez", "org.bluez.AgentManager1",
		"UnregisterAgent", g_variant_new("(o)", AGENT_PATH), NULL,
		G_DBUS_CALL_FLAGS_NONE, 5000, NULL, NULL);
	if (reply) g_variant_unref(reply);
	if (id) g_dbus_connection_unregister_object(bus, id);
	if (info) g_dbus_node_info_unref(info);
}

static void pair_done(GObject *source, GAsyncResult *result, gpointer user_data) {
	(void)user_data;
	GError *error = NULL;
	GVariant *reply = g_dbus_connection_call_finish(G_DBUS_CONNECTION(source), result, &error);
	if (!reply) {
		g_printerr("ERROR: %s\n", error ? error->message : "Bluetooth pairing failed");
		g_clear_error(&error); pair_ok = FALSE;
	} else {
		g_variant_unref(reply); pair_ok = TRUE;
	}
	g_main_loop_quit(pair_loop);
}

static int pair_device(const char *mac) {
	gchar *path = find_device(mac);
	if (!path) { g_printerr("ERROR: Bluetooth device %s was not discovered.\n", mac); return 2; }
	GDBusNodeInfo *info = NULL;
	guint agent_id = register_agent(&info);
	if (!agent_id) { g_free(path); return 3; }
	pair_ok = FALSE;
	pair_loop = g_main_loop_new(NULL, FALSE);
	g_dbus_connection_call(bus, BLUEZ_BUS, path, "org.bluez.Device1", "Pair", NULL, NULL,
		G_DBUS_CALL_FLAGS_NONE, 60000, NULL, pair_done, NULL);
	g_main_loop_run(pair_loop);
	g_main_loop_unref(pair_loop); pair_loop = NULL;
	if (pair_ok) pair_ok = set_property(path, "org.bluez.Device1", "Trusted", g_variant_new_boolean(TRUE));
	if (pair_ok) pair_ok = call_device(path, "Connect", 30000);
	unregister_agent(agent_id, info);
	g_free(path);
	return pair_ok ? 0 : 4;
}

static int device_method(const char *mac, const char *method) {
	gchar *path = find_device(mac);
	if (!path) { g_printerr("ERROR: Bluetooth device %s was not found.\n", mac); return 2; }
	gboolean ok = call_device(path, method, 30000);
	g_free(path);
	return ok ? 0 : 3;
}

static int print_name(const char *mac) {
	GError *error = NULL;
	GVariant *objects = managed_objects(&error);
	if (!objects) { g_clear_error(&error); return 2; }
	GVariantIter iter; const gchar *path; GVariant *interfaces; int rc = 2;
	g_variant_iter_init(&iter, objects);
	while (g_variant_iter_next(&iter, "{&o@a{sa{sv}}}", &path, &interfaces)) {
		GVariant *props = find_interface(interfaces, "org.bluez.Device1");
		if (props) {
			const gchar *address = NULL, *alias = NULL;
			g_variant_lookup(props, "Address", "&s", &address);
			if (address && g_ascii_strcasecmp(address, mac) == 0) {
				g_variant_lookup(props, "Alias", "&s", &alias);
				g_print("%s\n", alias ? alias : address); rc = 0;
			}
			g_variant_unref(props);
		}
		g_variant_unref(interfaces);
		if (!rc) break;
	}
	g_variant_unref(objects); return rc;
}

static void usage(const char *prog) {
	g_printerr("Usage: %s {power|devices|scan [seconds]|pair <MAC>|connect <MAC>|disconnect <MAC>|name <MAC>}\n", prog);
}

int main(int argc, char **argv) {
	if (argc < 2) { usage(argv[0]); return 2; }
	GError *error = NULL;
	bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, &error);
	if (!bus) { g_printerr("ERROR: %s\n", error->message); g_clear_error(&error); return 2; }
	int rc = 0;
	if (strcmp(argv[1], "power") == 0) rc = power_on() ? 0 : 2;
	else if (strcmp(argv[1], "devices") == 0) { if (!power_on()) rc = 2; else print_devices(); }
	else if (strcmp(argv[1], "scan") == 0) {
		int seconds = argc > 2 ? atoi(argv[2]) : 8; if (seconds < 2) seconds = 2; if (seconds > 30) seconds = 30;
		rc = power_on() ? scan_for(seconds) : 2;
	} else if ((strcmp(argv[1], "pair") == 0 || strcmp(argv[1], "connect") == 0 || strcmp(argv[1], "disconnect") == 0 || strcmp(argv[1], "name") == 0) && argc > 2) {
		if (!power_on()) rc = 2;
		else if (strcmp(argv[1], "pair") == 0) rc = pair_device(argv[2]);
		else if (strcmp(argv[1], "connect") == 0) rc = device_method(argv[2], "Connect");
		else if (strcmp(argv[1], "disconnect") == 0) rc = device_method(argv[2], "Disconnect");
		else rc = print_name(argv[2]);
	} else { usage(argv[0]); rc = 2; }
	g_object_unref(bus);
	return rc;
}
