import pytest
import brownie

from brownie import (
    StrategyControllerV1,
    StrategyControllerV2,
)


@pytest.mark.parametrize("Controller", [StrategyControllerV1, StrategyControllerV2])
def test_controller_deployment(gov, rewards, Controller):
    controller = gov.deploy(Controller, rewards)
    # Double check all the deployment variable values
    assert controller.governance() == gov
    assert controller.rewards() == rewards
    assert controller.onesplit() == "0x50FDA034C0Ce7a8f7EFDAebDA7Aa7cA21CC1267e"
    assert controller.split() == 500
    if controller._name == StrategyControllerV1._name:
        assert controller.strategist() == gov


@pytest.mark.parametrize(
    "name,val,Controller",
    [
        # V1
        ("Rewards", None, StrategyControllerV1),
        ("Strategist", None, StrategyControllerV1),
        ("Split", 1000, StrategyControllerV1),
        ("OneSplit", None, StrategyControllerV1),
        ("Governance", None, StrategyControllerV1),
        # V2
        ("Split", 1000, StrategyControllerV2),
        ("OneSplit", None, StrategyControllerV2),
        ("Governance", None, StrategyControllerV2),
    ],
)
def test_controller_setParams(accounts, gov, rewards, name, val, Controller):
    if not val:
        # Can't access fixtures, so use None to mean an address literal
        val = accounts[1]

    controller = gov.deploy(Controller, rewards)

    # Only governance can set this param
    with brownie.reverts("!governance"):
        getattr(controller, f"set{name}")(val, {"from": accounts[1]})
    getattr(controller, f"set{name}")(val, {"from": gov})
    assert getattr(controller, name.lower())() == val

    # When changing governance contract, make sure previous no longer has access
    if name == "Governance":
        with brownie.reverts("!governance"):
            getattr(controller, f"set{name}")(val, {"from": gov})
