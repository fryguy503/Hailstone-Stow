// Include from Hailstone's tests/inventory_manager_ui_test.cpp to run with the real UI, mock server and ImGui.
#include <span>

#include "plugin/policy.h"
#include "plugin/ui_bridge.h"
#include "core/ascii_case.h"
#include "net/door_packets.h"
#include "net/server_files_packets.h"
#include "net/trade_packets.h"

TEST_CASE("Stow add-on: real host keeps native Inventory independent of Stow Bags and Bank") {
    const fs::path stow = fs::absolute(fs::path(__FILE__).parent_path().parent_path());
    REQUIRE(fs::exists(stow / "ui" / "modern" / "bags.lua"));
    CHECK_FALSE(fs::exists(stow / "ui" / "modern" / "inventory.lua"));

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
    auto toolbox = bag_item(5010, "Crafting Toolbox", 26);
    toolbox.bag_type = 0x0a;
    auto part = make_item(5011, "Toolbox Component", 26);
    part.slot = at(26, 0);
    toolbox.contents.push_back({0, part});
    auto banked = bag_item(5004, "Bank Bag", 0);
    banked.slot = {net::kInvBank, 0, -1, -1};
    banked.bag_slots = 1;
    banked.bag_size = 4;
    auto personal_item = make_item(5012, "Personal bank item", 0);
    personal_item.slot = {net::kInvBank, 0, 0, -1};
    personal_item.no_rent = 255;
    banked.contents.push_back({0, personal_item});
    auto shared = bag_item(5005, "Shared Bag", 0);
    shared.slot = {net::kInvSharedBank, 0, -1, -1};
    shared.bag_slots = 1;
    shared.bag_size = 4;
    auto shared_item = make_item(5013, "Shared bank item", 0);
    shared_item.slot = {net::kInvSharedBank, 0, 0, -1};
    shared.contents.push_back({0, shared_item});
    auto transfer = make_item(5014, "Bank routing token", 28);
    transfer.no_rent = 255;
    config.characters[0].inventory.insert(config.characters[0].inventory.end(), {carried, quest, toolbox, transfer, banked, shared});
    for (std::int16_t slot = 1; slot < 24; ++slot) {
        auto filler = make_item(5200 + slot, "Bank filler " + std::to_string(slot), slot);
        filler.slot = {net::kInvBank, slot, -1, -1};
        config.characters[0].inventory.push_back(std::move(filler));
    }

    ScratchDir scratch("stow_host_smoke");
    auto options = quick_options();
    options.server_access_dir = scratch.path() / "server-files";
    Rig rig(std::move(config), options);
    constexpr std::string_view policy = "[commands]\nblock = /keypress\n";
    const auto bytes = std::as_bytes(std::span(policy));
    const net::ServerFilesPage page{1, 1, 0, {{static_cast<std::uint32_t>(bytes.size()), sha256(policy), "hailstone.cfg"}}};
    const net::ServerFilesChunk chunk{1, 0, 0, {bytes.begin(), bytes.end()}};
    rig.on_step = [&, next = std::size_t{0}, sent_list = false]() mutable {
        const auto& log = rig.server.zone_log;
        while (next < log.size()) {
            if (log[next++].opcode != net::kOpHsFilesRequest) continue;
            rig.server.zone.send_reliable(sent_list ? net::encode(chunk) : net::encode(page));
            sent_list = true;
        }
    };
    REQUIRE(rig.to_zone());
    auto& conn = rig.conn;
    const std::string denial(plugin::kDefaultCommandBlockedMessage);
    REQUIRE_FALSE(conn.server_command_allowed("/keypress"));
    conn.send_command("/keypress CLOSE_INV_BAGS");
    REQUIRE(has_line(rig.chat(), denial));
    put_coin_away(conn);
    auto character = conn.character_name();
    for (char& c : character) c = ascii_lower(c);
    const auto settings_prefix = "stow.stow-test%7C" + character + ".option.";
    const auto old_preference = settings_prefix + "replaceInventory";
    std::ofstream(scratch.path() / "settings.txt")
        << "plugin.script:stow." << old_preference << "=1\n"
        << "plugin.script:stow." << settings_prefix << "dockGrowth=up\n"
        << "plugin.script:stow.stow.compact.anchor.allBags=180,440\n"
        << "plugin.script:stow.stow.compact.anchor.bank=520,510\n";
    auto* ctx = ImGui::CreateContext();
    ImGui::GetIO().IniFilename = nullptr;
    ImGui::GetIO().BackendFlags |= ImGuiBackendFlags_RendererHasTextures;
    {
        plugin::UiBridge bridge;
        bool settings_requested = false;
        bridge.add_function("stow", "server_identity", [](const auto&) {
            return plugin::UiValue::string("stow-test");
        }, plugin::UiBridge::Kind::Script);
        bridge.add_function("stow", "take_settings_request", [&](const auto&) {
            return plugin::UiValue::boolean(std::exchange(settings_requested, false));
        }, plugin::UiBridge::Kind::Script);
        // The old script can still be loaded when the window code reloads.
        bridge.add_function("stow", "close_inventory_bags", [&](const auto&) {
            conn.send_command("/keypress CLOSE_INV_BAGS");
            return plugin::UiValue::boolean(true);
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
        auto locate_item = [&](ImGuiWindow& window, const char* label, float begin, float end, bool from_bottom)
            -> std::optional<ImVec2> {
            const auto target = window.GetID(label);
            auto& io = ImGui::GetIO();
            for (float offset = begin; offset < end; offset += 5.f) {
                const float y = window.Pos.y + (from_bottom ? window.Size.y - offset : offset);
                for (float from_left = 8.f; from_left <= window.Size.x - 3.f; from_left += 7.f) {
                    const ImVec2 point(window.Pos.x + from_left, y);
                    io.AddMousePosEvent(point.x, point.y);
                    frames(1);
                    if (ctx->HoveredId == target) return point;
                }
            }
            return std::nullopt;
        };
        auto hover = [&](const ImVec2& point) {
            ImGui::GetIO().AddMousePosEvent(point.x, point.y);
            frames(1);
        };
        auto click_item = [&](ImGuiWindow& window, const char* label, float begin, float end, bool from_bottom,
                              int button = ImGuiMouseButton_Left) {
            if (!locate_item(window, label, begin, end, from_bottom)) return false;
            auto& io = ImGui::GetIO();
            io.AddMouseButtonEvent(button, true);
            frames(1);
            io.AddMouseButtonEvent(button, false);
            frames(1);
            return true;
        };
        auto drag_dock = [&](ImGuiWindow& window, bool from_bottom, const ImVec2& destination) {
            if (!locate_item(window, "##stowDock.move", 3.f, 38.f, from_bottom)) return false;
            auto& io = ImGui::GetIO();
            io.AddMouseButtonEvent(ImGuiMouseButton_Left, true);
            frames(1);
            io.AddMousePosEvent(destination.x, destination.y);
            frames(1);
            io.AddMouseButtonEvent(ImGuiMouseButton_Left, false);
            frames(2);
            return true;
        };
        auto bank_item_id = [&](std::int16_t type, std::int16_t slot, std::int16_t sub = -1) {
            const auto* item = conn.inventory().at({type, slot, sub, -1});
            return item ? item->id : 0u;
        };

        frames();
        REQUIRE(api.replaces("InventoryWindow"));
        CHECK(run("return ui.GetSetting('" + old_preference + "')") == "1");
        api.toggle("InventoryWindow"); // The stock I key is routed through this toggle.
        frames();
        const auto* stock_inventory = ImGui::FindWindowByName("###modern.InventoryWindow");
        REQUIRE(stock_inventory != nullptr);
        CHECK(stock_inventory->Active);
        const auto* old_stow_inventory = ImGui::FindWindowByName("Stow###stow.inventory");
        CHECK((old_stow_inventory == nullptr || !old_stow_inventory->Active));
        CHECK(ImGui::FindWindowByName("Stow Bags###stow.allBags") == nullptr);
        api.toggle("InventoryWindow");
        frames();
        CHECK_FALSE(stock_inventory->Active);

        api.close_all_bags();
        api.toggle_all_bags(); // Shift+B dispatches to this native entry point.
        frames();
        auto* aggregated_bags = ImGui::FindWindowByName("Stow Bags###stow.allBags");
        REQUIRE(aggregated_bags != nullptr);
        CHECK(aggregated_bags->Active);
        const auto move_id = aggregated_bags->GetID("##stowDock.move");
        const auto stable_anchor = locate_item(*aggregated_bags, "##stowDock.move", 7.f, 36.f, true);
        REQUIRE(stable_anchor.has_value());
        const auto up_top = aggregated_bags->Pos.y;
        const auto expanded = aggregated_bags->Size;
        CHECK(expanded.x < 480.f);
        CHECK(expanded.y < 420.f);
        REQUIRE(click_item(*aggregated_bags, "##heading.inventory.new", 6.f, 70.f, false));
        frames();
        CHECK(run("return ui.GetSetting('stow.collapsed.inventory.new')") == "1");
        CHECK(aggregated_bags->Size.y < expanded.y);
        CHECK(aggregated_bags->Pos.y > up_top);
        hover(*stable_anchor);
        CHECK(ctx->HoveredId == move_id);
        REQUIRE(click_item(*aggregated_bags, "##heading.inventory.new", 6.f, 70.f, false));
        frames();
        CHECK(run("return ui.GetSetting('stow.collapsed.inventory.new')") == "0");
        CHECK(aggregated_bags->Size.y == doctest::Approx(expanded.y));
        CHECK(aggregated_bags->Pos.y == doctest::Approx(up_top));
        REQUIRE(run("assert(S.set('dockGrowth','down')); return 'ok'") == "ok");
        frames();
        const auto down_top = aggregated_bags->Pos.y;
        CHECK(down_top > up_top);
        hover(*stable_anchor);
        CHECK(ctx->HoveredId == move_id);
        REQUIRE(click_item(*aggregated_bags, "##heading.inventory.new", 24.f, 100.f, false));
        frames();
        CHECK(run("return ui.GetSetting('stow.collapsed.inventory.new')") == "1");
        CHECK(aggregated_bags->Pos.y == doctest::Approx(down_top));
        CHECK(aggregated_bags->Size.y < expanded.y);
        REQUIRE(click_item(*aggregated_bags, "##heading.inventory.new", 24.f, 100.f, false));
        frames();
        CHECK(aggregated_bags->Pos.y == doctest::Approx(down_top));
        REQUIRE(run("assert(S.set('dockGrowth','up')); return 'ok'") == "ok");
        frames();
        const auto platinum = conn.inventory_coin(0);
        REQUIRE(platinum > 0);
        conn.inventory_money_button(0, 1, nullptr);
        REQUIRE(conn.cursor_coins()[net::kCoinPlatinum] == 1u);
        REQUIRE(click_item(*aggregated_bags, "##stowCoin.IW_Money0", 14.f, 36.f, true));
        CHECK(conn.cursor_coins()[net::kCoinPlatinum] == 0u);
        CHECK(conn.inventory_coin(0) == platinum);
        REQUIRE(run(R"lua(
assert(S.actions())
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

        REQUIRE(run(R"lua(
assert(S.view("inventory", "grouped", "is:new").matched > 0)
for _, bag in ipairs(S.view("inventory", "bags").bags) do
  if bag.place == "i:26" then return tostring(S.setLocked(bag, true)) end
end
)lua") == "true");
        const auto moves_before_sort = MockEqServer::count(rig.server.zone_log, net::Op::MoveItem);
        REQUIRE(click_item(*aggregated_bags, "##stowDock.organize", 12.f, 48.f, true));
        REQUIRE(conn.item_job().has_value());
        CHECK(conn.item_job()->mode == net::GameConnection::ItemJobMode::Sort);
        CHECK(run("return tostring(S.view('inventory', 'grouped', 'is:new').matched)") == "0");
        REQUIRE(rig.until([&] { return !conn.item_job().has_value(); }));
        CHECK(MockEqServer::count(rig.server.zone_log, net::Op::MoveItem) > moves_before_sort);
        CHECK(id_at(conn, 26, 0) == part.id);

        auto new_quest = make_item(5300, "Etched Quest Seal", 30, 2);
        new_quest.quest_item = 1;
        REQUIRE(id_at(conn, 30) == 0u);
        conn.receive_zone_packet_for_test(net::encode_item_packet(false, {net::kItemPacketCharInventory, new_quest}));
        frames();
        REQUIRE(id_at(conn, 30) == new_quest.id);
        REQUIRE(run("return tostring(S.view('inventory', 'grouped', 'is:new').matched)") == "1");
        REQUIRE(click_item(*aggregated_bags, "##heading.inventory.new", 6.f, 85.f, false));
        frames();
        REQUIRE(run("return ui.GetSetting('stow.collapsed.inventory.new')") == "1");

        const auto before_clear = conn.inventory().revision();
        const auto moves_before_clear = MockEqServer::count(rig.server.zone_log, net::Op::MoveItem);
        REQUIRE(click_item(*aggregated_bags, "##stowCard.clearNew", 6.f, 85.f, false));
        frames();
        CHECK(run("return tostring(S.view('inventory', 'grouped', 'is:new').matched)") == "0");
        CHECK(run(R"lua(
for _, group in ipairs(S.view("inventory", "grouped").groups) do
  for _, cell in ipairs(group.cells) do
    if cell.place == "i:30" then return group.id end
  end
end
)lua") == "quest");
        CHECK_FALSE(conn.item_job().has_value());
        CHECK(conn.inventory().revision() == before_clear);
        CHECK(MockEqServer::count(rig.server.zone_log, net::Op::MoveItem) == moves_before_clear);
        CHECK(run("return ui.GetSetting('stow.collapsed.inventory.new')") == "1");

        ++new_quest.stack_count;
        conn.receive_zone_packet_for_test(net::encode_item_packet(false, {net::kItemPacketCharInventory, new_quest}));
        frames();
        CHECK(run("return tostring(S.view('inventory', 'grouped', 'is:new').matched)") == "1");

        REQUIRE(run("assert(S.set('dockGrowth','down')); return 'ok'") == "ok");
        frames();
        REQUIRE(drag_dock(*aggregated_bags, false, {-500.f, -500.f}));
        CHECK(aggregated_bags->Pos.x == doctest::Approx(0.f));
        CHECK(aggregated_bags->Pos.y == doctest::Approx(0.f));
        REQUIRE(run("assert(S.set('dockGrowth','up')); return 'ok'") == "ok");
        frames();
        REQUIRE(drag_dock(*aggregated_bags, true, {1800.f, 1300.f}));
        CHECK(aggregated_bags->Pos.x + aggregated_bags->Size.x == doctest::Approx(ImGui::GetIO().DisplaySize.x));
        CHECK(aggregated_bags->Pos.y + aggregated_bags->Size.y == doctest::Approx(ImGui::GetIO().DisplaySize.y));

        CHECK(run(R"lua(
local name, _, combine, scope = hs.UI.inventory.BagInfo("Bag2")
return tostring(name == "Crafting Toolbox" and combine and scope == "inventory")
)lua") == "true");
        const auto* separate_toolbox = ImGui::FindWindowByName("Crafting Toolbox###stow.Bag2");
        CHECK((separate_toolbox == nullptr || !separate_toolbox->Active));
        api.toggle("InventoryWindow");
        frames();
        CHECK(stock_inventory->Active);
        CHECK(aggregated_bags->Active);
        api.toggle("InventoryWindow");
        frames();
        CHECK_FALSE(stock_inventory->Active);
        CHECK(aggregated_bags->Active);
        api.toggle("InventoryWindow");
        frames();
        CHECK(stock_inventory->Active);
        api.toggle_all_bags();
        frames();
        CHECK_FALSE(aggregated_bags->Active);
        CHECK(stock_inventory->Active);
        api.toggle_all_bags();
        frames();
        CHECK(aggregated_bags->Active);
        CHECK(stock_inventory->Active);
        api.toggle("InventoryWindow");
        frames();
        CHECK_FALSE(stock_inventory->Active);
        CHECK(aggregated_bags->Active);

        (void)rig.chat();
        host.close_top_window = true; // The native Escape binding sets this for the UI pack.
        frames();
        CHECK_FALSE(aggregated_bags->Active);
        CHECK(run("return tostring(hs.UI.windows.Shown('Bag1'))") == "false");
        CHECK_FALSE(has_line(rig.chat(), denial));

        api.open_all_bags();
        frames();
        REQUIRE(aggregated_bags->Active);
        REQUIRE(click_item(*aggregated_bags, "##stowDock.close", 7.f, 36.f, true));
        frames();
        CHECK_FALSE(aggregated_bags->Active);
        CHECK(run("return tostring(hs.UI.windows.Shown('Bag1'))") == "false");
        CHECK_FALSE(has_line(rig.chat(), denial));
        api.close_all_bags(); // Reset the native toggle for the rest of this test.

        api.right_click_item(at(24));
        frames();
        const auto* satchel_window = ImGui::FindWindowByName("Tradeskill Satchel · Tradeskill only###stow.Bag1");
        REQUIRE(satchel_window != nullptr);
        CHECK(satchel_window->Active);
        auto& io = ImGui::GetIO();
        io.AddKeyEvent(ImGuiMod_Shift, true);
        io.AddKeyEvent(ImGuiKey_B, true);
        api.open_all_bags(); // The satchel was opened directly, so only the toolbox is new this frame.
        frames(1);
        CHECK(aggregated_bags->Active);
        separate_toolbox = ImGui::FindWindowByName("Crafting Toolbox###stow.Bag2");
        CHECK((separate_toolbox == nullptr || !separate_toolbox->Active));
        io.AddKeyEvent(ImGuiKey_B, false);
        io.AddKeyEvent(ImGuiMod_Shift, false);
        api.close_all_bags();
        frames(1);

        api.right_click_item(at(24));
        frames();
        io.AddKeyEvent(ImGuiMod_Ctrl, true);
        frames(1);
        api.right_click_item(at(26));
        io.AddKeyEvent(ImGuiMod_Ctrl, false);
        frames();
        auto* toolbox_window = ImGui::FindWindowByName("Crafting Toolbox###stow.Bag2");
        REQUIRE(toolbox_window != nullptr);
        CHECK(satchel_window->Active);
        CHECK(toolbox_window->Active);
        CHECK_FALSE(aggregated_bags->Active);
        REQUIRE(click_item(*toolbox_window, "Combine", 20.f, 85.f, false));
        REQUIRE(rig.until([&] { return MockEqServer::count(rig.server.zone_log, net::Op::TradeSkillCombine) == 1; }));
        for (const auto& packet : rig.server.zone_log) {
            if (net::from_wire(packet.opcode) == net::Op::TradeSkillCombine) {
                REQUIRE(packet.data.size() == net::kTradeSkillCombineSize);
                CHECK(std::to_integer<int>(packet.data[4]) == 26);
            }
        }
        rig.server.zone.send_reliable(net::AppPacket(net::to_wire(net::Op::TradeSkillCombine)));
        REQUIRE(rig.until([&] { return !conn.combine_pending(); }));
        api.close_all_bags();

        REQUIRE(conn.activate_bank(rig.server.config.own_spawn_id));
        api.show("BigBankWnd", true);
        frames();
        auto* bank_window = ImGui::FindWindowByName("Stow Bank###stow.bank");
        REQUIRE(bank_window != nullptr);
        CHECK(bank_window->Size.y < 420.f);
        CHECK(run("local v=S.view('shared', 'bags', ''); return tostring(v.live and v.bags[1].place=='s:0')") == "true");
        auto free_counts = [&](const char* expected) {
            CHECK(run("return S.view('bank', 'bags').free .. ':' .. S.view('shared', 'bags').free") == std::string(expected));
        };
        auto bank_counter = [&](const char* id, int button = ImGuiMouseButton_Left) {
            return click_item(*bank_window, id, 8.f, 53.f, true, button);
        };
        auto bank_slot = [&](const char* id) {
            return click_item(*bank_window, id, 5.f, bank_window->Size.y - 23.f, false);
        };
        auto bank_slot_visible = [&](const char* id) {
            return locate_item(*bank_window, id, 5.f, bank_window->Size.y - 23.f, false).has_value();
        };
        free_counts("0:1");
        conn.click_slot(at(28), false, false);
        REQUIRE(id_at(conn, net::kSlotCursor) == transfer.id);
        REQUIRE(run("return tostring(hs.UI.inventory.CanPlace('s:1'))") == "true");
        REQUIRE(bank_counter("##stowDock.empty.bank"));
        CHECK(id_at(conn, net::kSlotCursor) == transfer.id);
        CHECK(bank_item_id(net::kInvSharedBank, 1) == 0u);
        REQUIRE(bank_counter("##stowDock.empty.shared"));
        CHECK(id_at(conn, net::kSlotCursor) == 0u);
        CHECK(bank_item_id(net::kInvSharedBank, 1) == transfer.id);
        free_counts("0:0");
        REQUIRE(bank_slot("##b:0:0"));
        REQUIRE(id_at(conn, net::kSlotCursor) == personal_item.id);
        free_counts("1:0");
        REQUIRE(bank_counter("##stowDock.empty.shared"));
        CHECK(id_at(conn, net::kSlotCursor) == personal_item.id);
        CHECK(bank_item_id(net::kInvBank, 0, 0) == 0u);
        REQUIRE(bank_counter("##stowDock.empty.bank"));
        CHECK(id_at(conn, net::kSlotCursor) == 0u);
        CHECK(bank_item_id(net::kInvBank, 0, 0) == personal_item.id);

        REQUIRE(bank_slot("##b:0:0"));
        REQUIRE(id_at(conn, net::kSlotCursor) == personal_item.id);
        conn.click_slot(at(29), false, false);
        REQUIRE(id_at(conn, 29) == personal_item.id);
        REQUIRE(bank_slot("##s:1"));
        REQUIRE(id_at(conn, net::kSlotCursor) == transfer.id);
        free_counts("1:1");
        REQUIRE(bank_counter("##stowDock.empty.bank", ImGuiMouseButton_Right));
        CHECK(id_at(conn, net::kSlotCursor) == transfer.id);
        CHECK(bank_slot_visible("##b:0:0"));
        CHECK_FALSE(bank_slot_visible("##s:1"));
        REQUIRE(bank_counter("##stowDock.empty.shared", ImGuiMouseButton_Right));
        CHECK(bank_slot_visible("##b:0:0"));
        CHECK(bank_slot_visible("##s:1"));
        REQUIRE(bank_counter("##stowDock.empty.bank", ImGuiMouseButton_Right));
        CHECK_FALSE(bank_slot_visible("##b:0:0"));
        REQUIRE(bank_slot("##s:1"));
        CHECK(id_at(conn, net::kSlotCursor) == 0u);
        CHECK(bank_item_id(net::kInvSharedBank, 1) == transfer.id);
        conn.click_slot(at(29), false, false);
        REQUIRE(id_at(conn, net::kSlotCursor) == personal_item.id);
        REQUIRE(bank_counter("##stowDock.empty.bank", ImGuiMouseButton_Right));
        REQUIRE(bank_slot("##b:0:0"));
        CHECK(id_at(conn, net::kSlotCursor) == 0u);
        CHECK(bank_item_id(net::kInvBank, 0, 0) == personal_item.id);

        REQUIRE(bank_slot("##b:0:0"));
        REQUIRE(id_at(conn, net::kSlotCursor) == personal_item.id);
        REQUIRE(bank_counter("##stowDock.empty.bank", ImGuiMouseButton_Right));
        REQUIRE(run("assert(S.set('emptySlotsCard', true)); return 'ok'") == "ok");
        frames();
        REQUIRE(bank_slot("##stowSlot.empty.bank"));
        CHECK(id_at(conn, net::kSlotCursor) == 0u);
        CHECK(bank_item_id(net::kInvBank, 0, 0) == personal_item.id);
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

TEST_CASE("Stow add-on: the carried free-slot control fills stacks before using space") {
    constexpr std::uint32_t item_id = 6002;
    unsigned held_count = 1;
    unsigned second_count = 0;
    unsigned first_expected = 99;
    unsigned remaining = 0;
    bool incompatible = false;
    bool compact_tile = false;
    SUBCASE("the dock button merges a single item into a carried bag stack") {}
    SUBCASE("the compact Empty Slots tile fills multiple stacks and stows the remainder") {
        held_count = 5;
        second_count = 97;
        remaining = 2;
        compact_tile = true;
    }
    SUBCASE("an attuned stack with the same item ID stays in place") {
        held_count = 99;
        first_expected = 98;
        remaining = 99;
        incompatible = true;
    }

    const auto stack = [&](std::int16_t slot, unsigned count, std::uint32_t instance) {
        auto item = make_item(item_id, "Peridot", slot, count);
        item.max_stack = 99;
        item.instance_id = instance;
        item.serial = std::to_string(instance);
        if (incompatible) item.no_drop = 0; // Match the Lua-visible tradeability of the attuned stack.
        return item;
    };
    auto bag = bag_item(6001, "Component Pouch", 24);
    bag.bag_size = 4;
    auto first = stack(24, 98, 60020);
    first.attuned = incompatible;
    bag.contents.push_back({0, first});
    if (second_count) bag.contents.push_back({1, stack(24, second_count, 60021)});
    MockConfig config = MockConfig::standard();
    auto& inventory = config.characters[0].inventory;
    inventory.push_back(bag);
    inventory.push_back(bag_item(6003, "Travel Pouch", 26));
    inventory.push_back(stack(27, held_count, 60022));
    Rig rig(std::move(config), quick_options());
    REQUIRE(rig.to_zone());
    auto& conn = rig.conn;
    put_coin_away(conn);

    ScratchDir scratch("stow_cursor_stack_drop");
    const auto settings = scratch.path() / "settings.txt";
    std::ofstream(settings)
        << "plugin.script:stow.stow.stow-test%7Cgennro.option.dockGrowth=up\n"
        << "plugin.script:stow.stow.stow-test%7Cgennro.option.emptySlotsCard=" << compact_tile << '\n'
        << "plugin.script:stow.stow.compact.anchor.allBags=180,440\n";
    const std::unique_ptr<ImGuiContext, decltype(&ImGui::DestroyContext)> imgui(ImGui::CreateContext(),
                                                                             ImGui::DestroyContext);
    auto& io = ImGui::GetIO();
    io.IniFilename = nullptr;
    io.BackendFlags |= ImGuiBackendFlags_RendererHasTextures;
    plugin::UiBridge bridge;
    bridge.add_function("stow", "server_identity", [](const auto&) {
        return plugin::UiValue::string("stow-test");
    }, plugin::UiBridge::Kind::Script);
    app::UiHost host;
    host.in_game = host.ui_ready = true;
    host.game = &rig.game;
    host.conn = &conn;
    host.plugin_ui = &bridge;
    constexpr std::uint32_t caps = plugin::kCapRead | plugin::kCapUi | plugin::kCapActions;
    host.plugin_caps = [](std::string_view) { return caps; };
    app::UiApi api(host);
    api.load_layout(scratch.path() / "defaults.ini", scratch.path() / "UI.ini", {});
    ui::lua::LuaUi lua(ui_dir() / "modern", settings);
    lua.add_ui_api([&](lua_State* L) { api.register_functions(L); });
    lua.set_caller_scope([&](std::string_view tag) -> std::shared_ptr<void> {
        return std::make_shared<plugin::CallerScope>(caps, tag);
    });
    const auto stow = fs::absolute(fs::path(__FILE__).parent_path().parent_path());
    lua.set_folders({{"script:stow", stow / "ui" / "modern"}});
    const auto render = [&] {
        api.begin_frame();
        frame(lua);
        rig.step();
    };
    const auto free_slots = [&] {
        return std::stoi(lua.run_for_test("script:stow", "return tostring((hs.UI.inventory.InventorySpace()))"));
    };
    render();
    api.toggle_all_bags();
    conn.click_slot(at(27), true, false);
    REQUIRE(conn.inventory().cursor() != nullptr);
    CHECK(conn.inventory().cursor()->stack_count == held_count);
    REQUIRE(conn.inventory().at(at(24, 0)) != nullptr);
    CHECK((conn.inventory().at(at(24, 0))->attuned != 0) == incompatible);
    const auto free_before = free_slots();
    for (int i = 0; i < 3; ++i) render();
    auto* window = ImGui::FindWindowByName("Stow Bags###stow.allBags");
    REQUIRE(window != nullptr);
    REQUIRE(window->Active);
    const auto id = window->GetID(compact_tile ? "##stowSlot.empty.inventory" : "##stowDock.empty.inventory");
    for (float y = compact_tile ? window->Size.y - 5.f : 53.f;
         y >= 3.f && imgui->HoveredId != id; y -= 5.f) {
        for (float x = 8.f; x < window->Size.x && imgui->HoveredId != id; x += 7.f) {
            io.AddMousePosEvent(window->Pos.x + x, window->Pos.y + window->Size.y - y);
            render();
        }
    }
    REQUIRE(imgui->HoveredId == id);
    io.AddMouseButtonEvent(ImGuiMouseButton_Left, true);
    render();
    io.AddMouseButtonEvent(ImGuiMouseButton_Left, false);
    render();
    render();
    CHECK(ImGui::FindWindowByName("UI errors") == nullptr);
    CHECK(conn.inventory().cursor() == nullptr);

    const auto* first_after = conn.inventory().at(at(24, 0));
    REQUIRE(first_after != nullptr);
    CHECK(first_after->id == item_id);
    CHECK(first_after->stack_count == first_expected);
    CHECK((first_after->attuned != 0) == incompatible);
    CHECK(first_after->instance_id == first.instance_id);
    if (second_count) {
        const auto* second_after = conn.inventory().at(at(24, 1));
        REQUIRE(second_after != nullptr);
        CHECK(second_after->id == item_id);
        CHECK(second_after->stack_count == 99u);
    }
    CHECK(free_slots() == free_before - (remaining != 0));
    const auto unattuned_total = held_count + (incompatible ? 0u : first.stack_count) + second_count;
    CHECK(lua.run_for_test("script:stow", "local n = 0 "
        "for _, row in ipairs(hs.UI.inventory.AllItems()) do "
        "if row.where == 'carried' and row.item.id == 6002 and not row.item.attuned then n = n + row.item.count end "
        "end return tostring(n)") == std::to_string(unattuned_total));
}
