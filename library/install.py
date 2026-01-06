from ansible.module_utils.basic import AnsibleModule
from ansible.module_utils.installer.installer import Installer


def main():
    module = AnsibleModule(
        argument_spec=dict(
            recipe=dict(type="str", required=True),
            version=dict(type="str", required=False),
        ),
        supports_check_mode=True,
    )
    recipe_name = module.params["recipe"]
    version = module.params.get("version")

    if module.check_mode:
        module.exit_json(changed=True)

    installer = Installer(recipe_name, version)
    module.exit_json(changed=True)


if __name__ == "__main__":
    main()
