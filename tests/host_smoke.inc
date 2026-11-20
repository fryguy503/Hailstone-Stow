// Include from Hailstone's tests/inventory_manager_ui_test.cpp to run with the real UI, mock server and ImGui.
#include "plugin/policy.h"
#include "plugin/ui_bridge.h"
#include "net/trade_packets.h"

TEST_CASE("Stow add-on: real host loads inventory, bank, and bag presenters") {
    const fs::path stow = fs::absolute(fs::path(__FILE__).parent_path().parent_path());
    REQUIRE(fs::exists(stow / "ui" / "modern" / "inventory.lua"));

    MockConfig config = MockConfig::standard();
    auto carried = bag_item(5001, "Tradeskill Satchel", 24);
    carried.bag_type = 58;
    carried.bag_size = 3;
    carried.bag_slots = 32;
    auto material = make_item(5002, "Crafting Thread", 24);
    material.tradeskills = 1;
    carried.contents.push_back({0, material});
    for (std::uint32_t sub = 1; sub < 14; ++sub) {
        auto component = make_item(5100 + sub, "Crafting Component " + std::to_string(sub), 24);
        component.tradeskills = 1;
        carried.contents.push_back({sub, std::move(component)});
    }
    auto quest = make_item(5003, "Quest Seal", 25);
    quest.quest_item = 1;
    auto banked = bag_item(5004, "Bank Bag", 0);
    banked.slot = {net::kInvBank, 0, -1, -1};
    auto shared = bag_item(5005, "Shared Bag", 0);
    shared.slot = {net::kInvSharedBank, 0, -1, -1};
    config.characters[0].inventory.insert(config.characters[0].inventory.end(), {carried, quest, banked, shared});

    ScratchDir scratch("stow_host_smoke");
    Rig rig(std::move(config), quick_options());
    REQUIRE(rig.to_zone());
    auto& conn = rig.conn;
    put_coin_away(conn);
    auto* ctx = ImGui::CreateContext();
    ImGui::GetIO().IniFilename = nullptr;
    unsigned char* pixels = nullptr;
    int width = 0, height = 0;
    ImGui::GetIO().Fonts->GetTexDataAsRGBA32(&pixels, &width, &height);
    {
        plugin::UiBridge bridge;
        bool settings_requested = false;
        bridge.add_function("stow", "server_identity", [](const auto&) {
            return plugin::UiValue::string("stow-test");
        }, plugin::UiBridge::Kind::Script);
        bridge.add_function("stow", "take_settings_request", [&](const auto&) {
            return plugin::UiValue::boolean(std::exchange(settings_requested, false));
        }, plugin::UiBridge::Kind::Script);
        app::UiHost host;
        host.in_game = host.ui_ready = true;
        host.game = &rig.game;
        host.conn = &conn;
        host.plugin_ui = &bridge;
        std::uint32_t caps = plugin::kCapRead | plugin::kCapUi | plugin::kCapActions | plugin::kCapCommands;
        host.plugin_caps = [&](std::string_view) { return caps; };
        app::UiApi api(host);
        api.load_layout(scratch.path() / "defaults.ini", scratch.path() / "UI.ini", {});
        ui::lua::LuaUi lua(ui_dir() / "modern", scratch.path() / "settings.txt");
        lua.add_ui_api([&](lua_State* L) { api.register_functions(L); });
        lua.set_caller_scope([&](std::string_view tag) -> std::shared_ptr<void> {
            return std::make_shared<plugin::CallerScope>(caps, tag);
        });
        lua.set_folders({{"script:stow", stow / "ui" / "modern"}});
        auto frames = [&](int count = 3) {
            for (int i = 0; i < count; ++i) {
                api.begin_frame();
                frame(lua);
                rig.step();
            }
            CHECK(ImGui::FindWindowByName("UI errors") == nullptr);
        };
        auto run = [&](const std::string& body) {
            return lua.run_for_test("script:stow", "local S = dofile('lib/stow_model.lua') " + body);
        };
        auto click_item = [&](ImGuiWindow& window, const char* label, float begin, float end, bool from_bottom) {
            const auto target = window.GetID(label);
            auto& io = ImGui::GetIO();
            for (float offset = begin; offset < end; offset += 5.f) {
                const float y = window.Pos.y + (from_bottom ? window.Size.y - offset : offset);
                for (float from_left = 8.f; from_left <= window.Size.x - 3.f; from_left += 7.f) {
                    io.AddMousePosEvent(window.Pos.x + from_left, y);
                    frames(1);
                    if (ctx->HoveredId != target) continue;
                    io.AddMouseButtonEvent(ImGuiMouseButton_Left, true);
                    frames(1);
                    io.AddMouseButtonEvent(ImGuiMouseButton_Left, false);
                    frames(1);
                    return true;
                }
            }
            return false;
        };

        api.show("InventoryWindow", true);
        frames();
        auto* inventory_window = ImGui::FindWindowByName("Stow###stow.inventory");
        REQUIRE(inventory_window != nullptr);
        const auto expanded = inventory_window->Size;
        CHECK(expanded.x < 480.f);
        CHECK(expanded.y < 420.f);
        REQUIRE(click_item(*inventory_window, "##heading.inventory.new", 6.f, 70.f, false));
        frames();
        CHECK(run("return ui.GetSetting('stow.collapsed.inventory.new')") == "1");
        CHECK(inventory_window->Size.y < expanded.y);
        REQUIRE(click_item(*inventory_window, "##heading.inventory.new", 6.f, 70.f, false));
        frames();
        CHECK(run("return ui.GetSetting('stow.collapsed.inventory.new')") == "0");
        CHECK(inventory_window->Size.y == doctest::Approx(expanded.y));
        const auto platinum = conn.inventory_coin(0);
        REQUIRE(platinum > 0);
        conn.inventory_money_button(0, 1, nullptr);
        REQUIRE(conn.cursor_coins()[net::kCoinPlatinum] == 1u);
        REQUIRE(click_item(*inventory_window, "##stowCoin.IW_Money0", 14.f, 36.f, true));
        CHECK(conn.cursor_coins()[net::kCoinPlatinum] == 0u);
        CHECK(conn.inventory_coin(0) == platinum);
        REQUIRE(run(R"lua(
assert(S.actions())
assert(S.resetNew())
local data = S.view("inventory", "grouped", "is:quest")
assert(data.matched == 1)
local rows = S.view("inventory", "bags", "")
assert(rows.bags[1].item.bagType == 58)
for _, group in ipairs(rows.groups) do
  for _, cell in ipairs(group.cells) do
    if cell.place == "i:24:0" then return S.click(cell, "left") and "picked" end
  end
end
)lua") == "picked");
        CHECK(id_at(conn, net::kSlotCursor) == material.id);
        CHECK(run("return tostring(hs.UI.inventory.CanPlace('i:24:31'))") == "true");
        REQUIRE(run("return tostring(S.click({empty=true, where='carried', slot=24, sub=31, place='i:24:31'}, 'left'))") ==
            "true");
        CHECK(id_at(conn, 24, 31) == material.id);

        REQUIRE(conn.activate_bank(rig.server.config.own_spawn_id));
        api.show("BigBankWnd", true);
        frames();
        const auto* bank_window = ImGui::FindWindowByName("Stow Bank###stow.bank");
        REQUIRE(bank_window != nullptr);
        CHECK(bank_window->Size.y < 420.f);
        CHECK(run("local v=S.view('shared', 'bags', ''); return tostring(v.live and v.bags[1].place=='s:0')") == "true");
        CHECK(run("S.applyPreset('crafting'); return S.get('bankMode')") == "bags");
        frames();

        settings_requested = true;
        frames(19);
        CHECK(ImGui::FindWindowByName("Stow Settings###stow.settings") != nullptr);
        caps &= ~plugin::kCapActions;
        frames(64);
        CHECK(run("return tostring(S.actions())") == "false");
    }
    ImGui::DestroyContext(ctx);
}
