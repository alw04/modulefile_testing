return function(M)

    -- Default values for the module
    local defaults = {
        name = nil,
        version = nil,
        base = nil,
        description = nil,
        usage_notes = "",
        libraries_used = "",
        packages_used = "",
        optional_packages = "none",
        testing = "",
        website = nil,
        source = nil,
        built_by = "unknown",
        build_date = "unknown",
        prepend_paths = {},
        env_vars = {},
        -- load_modules = {},
        shell_functions = {},
        conflicts = {}
    }

    -- Fill in any missing fields from defaults
    for k, v in pairs(defaults) do
        if M[k] == nil then
            M[k] = v
        end
    end

    -- Make website and source name default to each other if only one is provided
    if M.source == nil and M.website ~= nil then
        M.source = M.website
    elseif M.website == nil and M.source ~= nil then
        M.website = M.source
    end

    -- If still missing, fallback to "N/A"
    M.source = M.source or "N/A"
    M.website = M.website or "N/A"

    local module_path = myFileName()

    -- Attempt to infer module name/version from its file path
    local name, version = module_path:match(".*/([^/]+)/([^/]+)%.lua$")
    M.name = M.name or name
    M.version = M.version or version

    if not M.name then
        LmodError("Module name could not be determined! Set M.name explicitly or fix modulefile path.")
    end

    if not M.version then
        LmodError("Module version could not be determined! Set M.version explicitly or fix modulefile path.")
    end

    -- Determine base install path
    M.base = M.base or
        (module_path:match("/software/el9/modulefiles/") and pathJoin("/software/el9/apps", M.name, M.version)) or
        (module_path:match("/reference/containers/modulefiles/") and pathJoin("/reference/containers", M.name, M.version))

    if not M.base then
        LmodError("Installation directory could not be determined! Set M.base explicitly or fix modulefile path.")
    elseif not isDir(M.base) then
        LmodError("Installation directory does not exist: " .. M.base)
    end

    -- Prepend standard subdirectories if they exist
    if M.base then
        local dir_env_map = {
            bin = {"PATH"},
            include = {"CPATH", "CMAKE_INCLUDE_PATH"},
            lib = {"LIBRARY_PATH", "LD_LIBRARY_PATH", "CMAKE_LIBRARY_PATH"},
            lib64 = {"LIBRARY_PATH", "LD_LIBRARY_PATH", "CMAKE_LIBRARY_PATH"},
            man = {"MANPATH"},
            ["share/man"] = {"MANPATH"},
            ["site-packages"] = {"PYTHONPATH"}
        }

        for subdir, env_vars in pairs(dir_env_map) do
            local full_path = pathJoin(M.base, subdir)
            if isDir(full_path) then
                for _, var in ipairs(env_vars) do
                    prepend_path(var, full_path)
                end
            end
        end
    end

    -- Add custom paths if provided
    if M.prepend_paths then
        for var, value in pairs(M.prepend_paths) do
            if isDir(value) then
                prepend_path(var, value)
            elseif mode() == "load" then
                LmodMessage("Warning: path does not exist: " .. value)
            end
        end
    end

    -- Set any module-specific environment variables
    if M.env_vars then
        for var, value in pairs(M.env_vars) do
            setenv(var, value)
        end
    end

    -- Set any module-specific conflicts
    if M.conflicts then
        for _, module in ipairs(M.conflicts) do
            conflict(module)
        end
    end

    -- if M.load_modules then
    --     for _, module in ipairs(M.load_modules) do
    --         -- if not isloaded(module) then
    --             load(module)
    --             -- LmodMessage(("Loaded dependency module: %s"):format(module))
    --         -- end
    --     end
    -- end

    -- Create shell functions for containers
    if M.shell_functions then
        for _, cmd in ipairs(M.shell_functions) do
            local path = pathJoin("$CONTAINERS", M.name, M.version, cmd .. "-" .. M.version .. ".sif")
            if isFile(path) then
                local bash_cmd = 'singularity exec ' .. path .. ' ' .. cmd .. ' "$@"'
                local csh_cmd = 'singularity exec ' .. path .. ' ' .. cmd .. ' $*'
                set_shell_function(cmd, bash_cmd, csh_cmd)
            elseif mode() == "load" then
                LmodMessage("Warning: container file not found for shell function '" .. cmd .. "': " ..path)
            end
        end
    end

    if mode() == "load" then
        LmodMessage(("Loaded module: %s/%s"):format(M.name, M.version))
    end

    if mode() == "unload" then
        LmodMessage(("Unloaded module: %s/%s"):format(M.name, M.version))
    end

    local bold = "\27[1m"
    local cyan = "\27[36m"
    local reset = "\27[0m"

    -- Default help message template
    help(([[
%s%s%s version %s%s

%sUsage Notes:%s
------------
%s
%s

%sLibraries Used:%s
---------------
%s

%sPackages Used:%s
--------------
%s

%sOptional Packages:%s
------------------
%s

%sTesting:%s
--------
$ module load %s/%s
%s

--
%sWebsite:%s %s
 %sSource:%s %s
   %sTest:%s See 'Testing' section above.
--
%sBuilt By:%s %s
%sBuild Date:%s %s
    ]]):format(
    bold, cyan, M.name, M.version, reset, -- Title

    cyan, reset, -- Usage Notes
    M.name,
    M.usage_notes,

    cyan, reset, -- Libraries Used
    M.libraries_used,

    cyan, reset, -- Packages Used
    M.packages_used,

    cyan, reset, -- Optional Packages
    M.optional_packages,

    cyan, reset, -- Testing
    M.name, M.version,
    M.testing,

    cyan, reset, M.website, -- Website
    cyan, reset, M.source, -- Source
    cyan, reset, -- Test

    cyan, reset, M.built_by, --Built By
    cyan, reset, M.build_date -- Build Date
    ))

    -- Provide description if missing
    if not M.description then
        M.description = ("%s is ..."):format(M.name)
    end

    whatis(("Name: %s"):format(M.name))
    whatis(("Description: %s"):format(M.description))
    whatis(("Version: %s"):format(M.version))
end
