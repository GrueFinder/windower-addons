_addon.name = 'NyzulMyMule'
_addon.author = 'GrueFinder'
_addon.version = '1.0.0'
_addon.commands = {'nmm','nyzulmymule'}

require('logger')
texts = require('texts')
packets = require('packets');
config = require('config');

local defaults = {
    auto_navigate = {
        starting_floor = 1,
        min_time_remaing = 480, -- 8 Minutes
        mule_name = '',
        enabled = false,
    },
    display = {
        pos = {
            x = 450,
            y = 0,
        },
        text = {
            font = 'Consolas',
            size = 12,
        },
    },
    zoning_wait_time = 30,
    interval = 0.1,
    debugging = false,
};
local settings = config.load(defaults);

local save_settings = function()
    config.save(settings, 'all');
end

local msg = {}
msg.add_to_chat = function(message)
    windower.add_to_chat(207, _addon.name .. ': ' .. message);
end
msg.add_to_logs = function(message)
    if (settings.debugging) then
        windower.add_to_chat(207, _addon.name .. ': [DBG] ' .. message);
    end
end
msg.echo_to_all = function(message, all)
    local player = windower.ffxi.get_player();
    windower.send_ipc_message('echo (%s) %s':format(player.name, message));
    msg.add_to_chat(message);
end
    
local context = {
    commands = {},
    ismule = false,
    is_menu_active = false,
    is_nni = false,
    menus = {},
    queue = {
        count = 0,
    },
    status = {
        frame_time = 0,
        zone_timer = 0,
        end_time = nil,
    },
    navcmd = '',
    navarg = nil,
    running = false,
};
context.reset = function()
    context.status.zone_timer = 0;
    context.status.end_time = nil;
end

local append_menuwait_delay;
local append_queue_commands;
local execute_command_queue;
local distance_sqd;
local find_nearest_target;
local move_to_target;
local interact_with_npc;
local set_timer;
local update_status;

context.commands['abort'] = {
    all_chars = true,
    process = function(command, args)
        context.commands.forward(command, args);
        context.navcmd = command;
        interact_with_npc('Rytaal');
    end,
    help_text = 'nmm abort -- Cancels your current assault orders with Rytaal',
};
context.commands['assault'] = {
    all_chars = true;
    process = function(command, args)
        context.commands.forward(command, args);
        context.navcmd = command;
        interact_with_npc('Runic Portal', true);
    end,
    help_text = 'nmm assault -- transport everyone to NyZule Isle',
};
context.commands['auto'] = {
    all_chars = true,
    process = function(command, args)
        context.commands.forward(command, args);
        if (#args <= 0) then
        elseif (args[1]:lower() == 'on') and (not settings.auto_navigate.enabled) then
            settings.auto_navigate.enabled = true;
        elseif (args[1]:lower() == 'off') and (settings.auto_navigate.enabled) then
            settings.auto_navigate.enabled = false;
        end
        if (context.ismule) then
            if settings.auto_navigate.enabled then
                msg.echo_to_all('Auto-Navigation is ON');
            else
                msg.echo_to_all('Auto-Navigation is OFF');
            end
        end
        save_settings();
    end,
    help_text = 'nmm auto [on|off] -- Turns automatic navigation on or off',
};
context.commands['debug'] = {
    all_chars = false,
    process = function(command, args)
        if (#args <= 0) then
        elseif (args[1]:lower() == 'on') and (not settings.debugging) then
            settings.debugging = true;
        elseif (args[1]:lower() == 'off') and (settings.debugging) then
            settings.debugging = false;
        end
        if (settings.debugging) then
            msg.echo_to_all('Debug Messages are ON');
        else
            msg.echo_to_all('Debug Messages are OFF');
        end
        save_settings();
    end,
    help_text = 'nmm debug [on|off] -- Turns debug logging on or off',
};
context.commands['echo'] = {
    all_chars = true,
    process = function(command, args)
        if #args >= 1 and args[#args] == 'nofwd' then
            table.remove(args, #args);
        end
        msg.add_to_chat(table.concat(args, ' '));
    end,
    help_text = nil,
};
context.commands['enter'] = {
    all_chars = false,
    process = function(command, args)
        if context.commands.forward(command, args) then return; end
        if (#args >= 1) then
            context.navarg = args[1];
        else
            context.navarg = nil;
        end
        msg.echo_to_all('Executing Command: ' .. command .. ' (Floor ' .. context.navarg .. ')');
        context.navcmd = command;
        interact_with_npc('Rune of Transfer', true);
    end,
    help_text = 'nmm enter <floor> -- Enters Nyzul at the given floor',
};
context.commands['exit'] = {
    all_chars = false,
    process = function(command, args)
        if context.commands.forward(command, args) then return; end
        msg.echo_to_all('Executing Command: ' .. command);
        context.navcmd = command;
        interact_with_npc('Rune of Transfer', false);
    end,
    help_text = 'nmm exit -- Exits Nyzul and returns to the staging point',
};
context.commands['finish'] = {
    all_chars = true,
    process = function(command, args)
        context.commands.forward(command, args);
        context.commands['target'].process('target', {'Rytaal'});
    end,
    help_text = 'nmm finish -- turns in your completed tags to Rytaal',
};
context.commands['floor'] = {
    all_chars = false,
    process = function(command, args)
        if (#args >= 1) then
            local value = tonumber(args[1]);
            if (not value) then
                msg.echo_to_all('Floor ' .. args[1] .. ' is not valid!!!');
                return;
            end

            if (value >= 100) then value = 100; end
            if (value <= 0x0) then value = 0x1; end
            if ((value%5)==0) then value = (value - 1); end
            value = (value - (value % 5) + 1);
            
            if (settings.auto_navigate.starting_floor ~= value) then
                settings.auto_navigate.starting_floor = value;
                save_settings();
            end
        end
        msg.echo_to_all('Starting Floor is ' .. settings.auto_navigate.starting_floor);
    end,
    help_text = 'nmm floor <number> -- Starts at <floor> when Auto Navigation is ON',
};
context.commands['goup'] = {
    all_chars = false,
    process = function(command, args)
        if context.commands.forward(command, args) then return; end
        msg.echo_to_all('Executing Command: ' .. command);
        context.navcmd = command;
        interact_with_npc('Rune of Transfer', false);
    end,
    help_text = 'nmm goup -- Goes to the next floor (both reg and NNI)',
};
context.commands['help'] = {
    all_chars = false,
    process = function(command, args)
        local tkeys = {}
        for id, cmd in pairs(context.commands) do
            if type(cmd) == 'table' then
                if (cmd.help_text) then
                    table.insert(tkeys, id);
                end
            end
        end
        
        table.sort(tkeys);
        for _, id in ipairs(tkeys) do
            local cmd = context.commands[id];
            msg.add_to_chat(cmd.help_text);
        end
    end,
    help_text = 'nmm help -- Displays the current help text',
};
context.commands['jump'] = {
    all_chars = false,
    process = function(command, args)
        if context.commands.forward(command, args) then return; end
        msg.echo_to_all('Executing Command: ' .. command);
        context.navcmd = command;
        interact_with_npc('Rune of Transfer', false);
    end,
    help_text = 'nmm jump -- Goes up several floors (for NNI only)',
};
context.commands['mule'] = {
    all_chars = true,
    process = function(command, args)
        if #args >= 1 and type(args[1]) == 'string' then
            context.commands.setmule(args[1]);
            settings.auto_navigate.mule_name = args[1];
            save_settings();
            context.commands.forward(command, args);
        elseif (settings.auto_navigate.mule_name ~= '') then
            msg.add_to_chat('%s is currently the designated mule':format(settings.auto_navigate.mule_name));
        else
            msg.add_to_chat('[ERR] You have not designated a mule yet!!!');
        end
    end,
    help_text = 'nmm mule <name> -- sets the lamp mule',
};
context.commands['nni'] = {
    all_chars = true,
    process = function(command, args)
        windower.send_command('nmm orders nni');
    end,
    help_text = 'nmm nni -- Gets assault orders from Sorrowful Sage for NNI',
};
context.commands['orders'] = {
    all_chars = true,
    process = function(command, args)
        context.commands.forward(command, args);
        context.navcmd = command;
        context.navarg = (#args >= 1 and args[1] == 'nni') and 'nni' or 'nyzul'
        context.is_nni = context.navarg == 'nni'
        interact_with_npc('Sorrowful Sage');
    end,
    help_text = 'nmm orders -- Gets assault orders from Sorrowful Sage for regular Nyzul',
};
context.commands['reload'] = {
    all_chars = true,
    process = function(command, args)
        context.commands.forward(command, args);
        windower.send_command('lua reload ' .. _addon.name);
    end,
    help_text = 'nmm reload -- Reloads the addon',
};
context.commands['return'] = {
    all_chars = true,
    process = function(command, args)
        context.commands.forward(command, args);
        context.navcmd = command;
        interact_with_npc('Runic Portal', true);
    end,
    help_text = 'nmm return -- Returns to Whitegate (after exiting Nyzul)',
};
context.commands['save'] = {
    all_chars = false,
    process = function(command, args)
        save_settings();
        msg.echo_to_all('Settings file saved!');
    end,
    help_text = 'nmm save -- saves the current settings';
};
context.commands['settings'] = {
    all_chars = false,
    process = function(command, args)
        if settings.debug then table.vprint(settings); end
    end,
    help_text = nil,
};
context.commands['target'] = {
    all_chars = false,
    process = function(command, args)
        if (#args <= 0) then
            return;
        end
        local name = table.concat(args, ' ');

        context.running = false;
        msg.add_to_logs('Attempting to target "' .. name .. '"...');
        interact_with_npc(name);
    end,
    help_text = 'nmm target <name> -- Targets and clicks the closest NPC matching <name>',
};
context.commands['tags'] = {
    all_chars = true,
    process = function(command, args)
        context.commands.forward(command, args);
        context.navcmd = command;
        interact_with_npc('Rytaal');
    end,
    help_text = 'nmm tags -- Gets tags from Rytaal',
};

context.commands.execute = function(name, ...)
    local cmd = nil;
    if (name) then
        name = name:lower();
        cmd = context.commands[name];
    end
    local args = T{...};
    local nofwd = (#args >= 1 and args[#args] == 'nofwd') and true or false;
    
    if (name) and (cmd) then
        if nofwd and not cmd.all_chars and not context.ismule then
            print('aborting')
            return;
        end        
        context.running = true;
        context.commands[name].process(name, args);
    elseif (name) then
        msg.add_to_chat('[ERR] Unrecognized command "' .. name .. '"!!!');
        context.commands['help'].process('help', {});
    end
end;

context.commands.forward = function(command, args)
    local info = context.commands[command];
    if not context.ismule or (info and info.all_chars) then
        if #args == 0 or (#args >= 1 and args[#args] ~= 'nofwd') then
            windower.send_ipc_message('%s %s':format(command, table.concat(args, ' ')))
            return true;
        end
    end
    return false;
end

context.commands.setmule = function(name)
    local player = windower.ffxi.get_player();
    if name:lower() == player.name:lower() then
        context.ismule = true;
        msg.echo_to_all('I am now the lamp mule!');
    else
        context.ismule = false;
    end;
end

context.menus[0x053] = { -- Floor Selection
    handler = function(id, data, modified, injected, blocked)
        local requested = 96;
        if (context.navarg) then
            requested = tonumber(context.navarg);
            if (requested >= 100) then requested = 100; end
            if (requested <= 0x0) then requested = 0x1; end
            if ((requested%5)==0) then requested = (requested - 1); end
            requested = (requested - (requested % 5) + 1);
        end
        msg.add_to_logs('Attempting to Select Floor ' .. requested .. '...');
        
        local selection = 1;
        while (requested > 1) do
            selection = (selection + 1);
            requested = (requested - 5);
        end

        append_menuwait_delay();
        append_queue_commands('down',  selection);
        append_queue_commands('enter', 1);
        append_menuwait_delay();
        append_queue_commands('up',    1);
        append_queue_commands('enter', 1);
        execute_command_queue();
    end,
};
context.menus[0x05E] = context.menus[0x053];
context.menus[0x060] = { -- NNI Floor Selection
    handler = function(id, data, modified, injected, blocked)
        local requested = 96;
        if (context.navarg) then
            requested = tonumber(context.navarg);
            if (requested >= 100) then requested = 100; end
            if (requested <= 0x0) then requested = 0x1; end
            if ((requested%20)==0) then requested = (requested - 1); end
            requested = (requested - (requested % 5) + 1);
        end
        msg.add_to_logs('Attempting to Select Floor ' .. requested .. '...');
        
        local selection = 1;
        while (requested > 1) do
            selection = (selection + 1);
            requested = (requested - 20);
        end

        append_menuwait_delay();
        append_queue_commands('down',  selection);
        append_queue_commands('enter', 1);
        append_menuwait_delay();
        append_queue_commands('up',    1);
        append_queue_commands('enter', 1);
        execute_command_queue();
    end,
};
context.menus[0x075] = { -- Runic Portal (Assault Area Entrance/Exit)
    handler = function(id, data, modified, injected, blocked)
        if (context.navcmd == 'assault') then
            append_menuwait_delay();
            append_queue_commands('up',    1);
            append_queue_commands('enter', 1);
            execute_command_queue();
        elseif (context.navcmd == 'return') then
            append_menuwait_delay();
            append_queue_commands('up',    1);
            append_queue_commands('enter', 1);
            execute_command_queue();
        end
    end,
};
context.menus[0x076] = context.menus[0x075];
context.menus[0x07D] = context.menus[0x075];
context.menus[0x0C9] = { -- Rune of Transfer
    handler = function(id, data, modified, injected, blocked)
        if (context.navcmd == 'goup') or (context.navcmd == 'jump') then
            append_menuwait_delay();
            if (context.navcmd == 'jump') then
                append_queue_commands('down',  3);
            else
                append_queue_commands('down',  2);
            end
            append_queue_commands('enter', 1);
            execute_command_queue();
        elseif (context.navcmd == 'exit') then
            append_menuwait_delay();
            append_queue_commands('down',  1);
            append_queue_commands('enter', 1);
            append_menuwait_delay();
            append_queue_commands('up',    1);
            append_queue_commands('enter', 1);
            execute_command_queue();
        end
    end,
};
context.menus[0x10C] = { -- Rytaal
    handler = function(id, data, modified, injected, blocked)
        if context.navcmd == 'tags' then
            append_menuwait_delay();
            append_queue_commands('enter', 1);
            execute_command_queue();
        elseif context.navcmd == 'abort' then
            append_menuwait_delay();
            append_queue_commands('down',  1);
            append_queue_commands('enter', 1);
            append_menuwait_delay();
            append_queue_commands('up',    1);
            append_queue_commands('enter', 1);
            execute_command_queue();
        end
    end,
};
context.menus[0x116] = { -- Sorrowful Sage
    handler = function(id, data, modified, injected, blocked)
        append_menuwait_delay();
        append_queue_commands('enter', 1);
        append_menuwait_delay();
        if (context.navarg == 'nni') then
            append_queue_commands('down', 1);
        end
        append_queue_commands('enter', 1);
        append_menuwait_delay();
        append_queue_commands('up',    1);
        append_queue_commands('enter', 1);
        execute_command_queue();
    end,
};

local gui = texts.new(settings.display, settings);
initialize = function(text, settings)
    local properties = L{}
	properties:append('Time Remaining: ${timer_color}${timer_value|-|%5s}\\cr')	
    text:clear()
    text:append(properties:concat('\n'))
end
gui:register_event('reload', initialize);

context.commands['show'] = {
    process = function(command, args)
        gui:show();
    end,
    help_text = 'nmm show -- Shows the time remaining widget',
};
context.commands['hide'] = {
    process = function(command, args)
        gui:hide();
    end,
    help_text = 'nmm hide - Hides the time remaining widget',
};

append_menuwait_delay = function()
    append_queue_commands(nil, 6);
end

append_queue_commands = function(name, count)
    for i = 1, count do
        local index = context.queue.count + 1;
        if (not name) or (name == "") then
            context.queue[index] = 'pause 0.2;';
        else
            context.queue[index] = 'setkey ' .. name .. ' down; pause 0.1; setkey ' .. name .. ' up; pause 0.1;';
        end
        context.queue.count = index;
    end
end

execute_command_queue = function()
    local commands = { count = 0, };
    local index = 0;

    for i = 1, context.queue.count do
        if ((i % 5) == 1) or (commands.count == 0) then
            index = commands.count + 1;
            commands[index] = "";
            commands.count = index;
        end
        commands[index] = (commands[index] .. context.queue[i]);
    end
    msg.add_to_logs("Command Count is " .. commands.count);
    
    for i = 1, commands.count do
        if (i ~= 1) then
            msg.add_to_logs('Sleeping...');
            coroutine.sleep(1);
        end
        msg.add_to_logs('Sending: ' .. commands[i]);
        windower.send_command(commands[i]);
    end
    
    context.queue = { count = 0, };
    context.running = false;
end

distance_sqd = function(a, b)
    local dx, dy = b.x-a.x, b.y-a.y
    return dy*dy + dx*dx
end

find_nearest_target = function(name)
    local candidate = {
        target = nil,
        distance = nil,
    };
    local player = windower.ffxi.get_mob_by_target('me');
    
    for i, mob in pairs(windower.ffxi.get_mob_array()) do
        
        if (windower.wc_match(mob.name, name)) then
            local d = distance_sqd(mob, player);
            if mob.valid_target and (not candidate.distance or d < candidate.distance) then
                candidate.target = mob;
                candidate.distance = d:sqrt();
            end
        end
        
    end
    return candidate.target, candidate.distance;
end

move_to_target = function(target)
    msg.add_to_logs('Moving to target "' .. target.name .. '"...');
    
    local player = windower.ffxi.get_mob_by_target("me");
    local distance = distance_sqd(target, player);
    local vector = {
        x = (target.x - player.x),
        y = (target.y - player.y),
        z = (target.z - player.z),
    };
    windower.ffxi.run(vector.x, vector.y, vector.z);

    while (distance >= 5.75) do
        coroutine.sleep(1);
        player = windower.ffxi.get_mob_by_target("me");
        distance = distance_sqd(target, player);
    end
    windower.ffxi.run(false);

    return distance;
end

interact_with_npc = function(name, move)
    local target, yalms = find_nearest_target(name);
    if (not target) then
        msg.echo_to_all('Target Not Found!!!');
        return;
    end
    msg.add_to_logs('Found target "' .. target.name .. '" (ID = ' .. target.id .. ', IDX = ' .. target.index .. ')');
    
    if (move and yalms >= 5.75) then
        msg.add_to_logs('Target is out of range!!!');
        yalms = move_to_target(target);
    end
    
    if (yalms > 5.75) then
        msg.echo_to_all('Target out of range!');
        return;
    elseif (not target.is_npc) then
        msg.echo_to_all('Cannot select non-NPC targets!');
        return;
    end
    
    local pkg = packets.new('outgoing', 0x01A, {
        ["Target"] = target.id,
        ["Target Index"] = target.index,
        ["Category"] = 0,
        ["Param"] = 0,
        ["_unknown1"] = 0
    });
    packets.inject(pkg);
    msg.add_to_logs('Sent poke packet!!!');
end

set_timer = function(remaining)
    msg.add_to_logs('Time Remaing Set to ' .. remaining);
    context.status.zone_timer = remaining;
    context.status.end_time = (os.time() + context.status.zone_timer);
end

update_status = function()

    local info = {
        timer_color = '',
        timer_value = os.date('%M:%S', context.status.zone_timer),
    };
    if context.status.zone_timer < 60 then 
        info.timer_color = '\\cs(255,0,0)';
    end
    gui:update(info);
    
end

windower.register_event('addon command', function(command, ...)
    context.commands.execute(command, ...);
end);

windower.register_event('incoming chunk', function(id, data, modified, injected, blocked)
    if (context.running) and (id == 0x032 or id == 0x034) then
        local handler = nil;
        local p = packets.parse('incoming', data);
        local menu_id = p["Menu ID"];
        msg.add_to_logs('Received Interaction Packet (%s:%s)':format(menu_id, id));
        
        local menu = nil;
        if (context.menus and context.menus[menu_id]) then
            menu = context.menus[menu_id];
        else
            msg.add_to_logs('Unknown menu_id (%s)':format(menu_id));
        end
        if (menu) and (menu.handler) then
            context.is_menu_active = true;
            menu.handler:schedule(0, id, data, modified, injected, blocked);
        end
    elseif (settings.debug) and (id == 0x032 or id == 0x034) then
        local p = packets.parse('incoming', data);
        local menu_id = p["Menu ID"];
        msg.add_to_logs('Received menu_id (%s:%s)':format(menu_id, id));
    end
end);

windower.register_event('outgoing chunk', function(id, data, modified, injected, blocked)
    if id == 0x05B then context.is_menu_active = false; end
end);

windower.register_event('action message',function (actor_id, target_id, actor_index, target_index, message_id, param_1, param_2, param_3)
    msg.add_to_logs('Received Action Message %s':format(message_id));
end)

windower.register_event('incoming text', function(original, modified, mode, _, blocked)

    local info = windower.ffxi.get_info()
    if (not info.logged_in) or (info.zone ~= 77 and info.zone ~= 50) or (blocked) or (original == '') then
        return;
    end

    if (context.is_menu_active) then
        if (mode == 150 or mode == 151) and (not original:match(string.char(0x1e, 0x02))) then
            modified = modified:gsub(string.char(0x7F, 0x31), '');
            return modified;
        end
    end

    if (mode == 123) then

        if string.find(original, 'Time limit has been reduced') then
            local penalty = original:match('%d+');
            set_timer(context.status.zone_timer - (tonumber(penalty) * 60));
        end

    elseif (mode == 146) or (mode == 148) then
    
        if (string.find(original, '(Earth time)')) then
        
            local multiplier = 1;
            if string.find(original, 'minute') then
                multiplier = 60;
            end    
            set_timer(tonumber(original:match('%d+')) * multiplier);
        
        elseif (string.find(original,'Floor %d+ objective complete. Rune of Transfer activated.')) then

            if context.ismule and settings.auto_navigate.enabled then
                if (context.status.zone_timer < settings.auto_navigate.min_time_remaing) then
                    context.commands.execute('exit');
                else
                    context.commands.execute('goup');
                end
            end

        end

    end
    
end);

windower.register_event('ipc message', function(message)
    windower.send_command('nmm %s nofwd':format(message));
    msg.add_to_logs('Received "%s"':format(message));
end);

windower.register_event('load', function()
    
    local info = windower.ffxi.get_info()
    if (info.logged_in) then
        context.commands.setmule(settings.auto_navigate.mule_name);
        if (info.zone == 77) then
            if (settings.end_time) and (settings.end_time > os.time()) then
                context.status.end_time = settings.end_time;
                context.status.zone_timer = (settings.end_time - os.time());
            end
            if context.ismule and settings.auto_navigate.enabled then
                context.commands.execute('enter', settings.auto_navigate.starting_floor);
            end
            gui:show();
        end
    end

end);

windower.register_event('prerender', function()
    local curr = os.clock();
    if (curr > (context.status.frame_time + settings.interval)) then
        if (context.status.end_time ~= nil) and (context.status.zone_timer >= 1) and (context.status.zone_timer ~= (context.status.end_time - os.time())) then
            context.status.zone_timer = (context.status.end_time - os.time());
        end
        context.status.frame_time = curr;
        update_status();
    end
end);

windower.register_event('unload', function()

    local info = windower.ffxi.get_info()
    if (info.logged_in) and (info.zone == 77) then 
        settings.end_time = context.status.end_time;
        save_settings();
    end
    
end);

windower.register_event('zone change', function(new, old)

    gui:hide();
    if (new == 72) and (old == 77) then
        context.status.zone_timer = 0;
    else
        context.reset();
    end
    if (new == 77) then
        if context.ismule and settings.auto_navigate.enabled then
            coroutine.schedule(function()
                context.commands.execute('enter', settings.auto_navigate.starting_floor);
            end, settings.zoning_wait_time);
        end
        gui:show();
    end
    
end)
