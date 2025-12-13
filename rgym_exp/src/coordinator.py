import json
import requests
from genrl.logging_utils.global_defs import get_logger
from genrl.blockchain.connections import get_contract, send_via_api as _original_send_via_api, setup_web3
from genrl.blockchain.coordinator import SwarmCoordinator

# Force device status check (embedded in business logic, cannot bypass)
try:
    from rgym_exp.src.device_check import verify_device_before_api_call, require_device_enabled
    DEVICE_CHECK_AVAILABLE = True
except ImportError:
    # If device_check module is deleted, all API calls will fail
    DEVICE_CHECK_AVAILABLE = False
    def verify_device_before_api_call():
        raise RuntimeError("Device check module is missing. API calls are disabled.")
    def require_device_enabled(func):
        def wrapper(*args, **kwargs):
            raise RuntimeError("Device check module is missing. API calls are disabled.")
        return wrapper

# Wrap send_via_api function, force check at low level
def send_via_api(org_id, modal_proxy_url, method, args):
    """
    Wrapped send_via_api function, force device status check before all API calls
    Even if upper level code removes checks, this will still check
    """
    verify_device_before_api_call()
    return _original_send_via_api(org_id, modal_proxy_url, method, args)


class ModalSwarmCoordinator(SwarmCoordinator):
    def __init__(
        self,
        web3_url: str,
        contract_address: str,
        org_id: str,
        modal_proxy_url: str,
        swarm_coordinator_abi_json: str,
    ) -> None:
        super().__init__(web3_url, contract_address, swarm_coordinator_abi_json)
        self.org_id = org_id
        self.modal_proxy_url = modal_proxy_url

    def register_peer(self, peer_id):
        verify_device_before_api_call()
        try:
            send_via_api(
                self.org_id, self.modal_proxy_url, "register-peer", {"peerId": peer_id}
            )
        except requests.exceptions.HTTPError as http_err:
            if http_err.response is None or http_err.response.status_code != 400:
                raise

            try:
                err_data = http_err.response.json()
                err_name = err_data["error"]
                if err_name != "PeerIdAlreadyRegistered":
                    get_logger().info(f"Registering peer failed with: f{err_name}")
                    raise
                get_logger().info(f"Peer ID [{peer_id}] is already registered! Continuing.")

            except json.JSONDecodeError as decode_err:
                get_logger().debug(
                    "Error decoding JSON during handling of register-peer error"
                )
                raise http_err

    def submit_reward(self, round_num, stage_num, reward, peer_id):
        verify_device_before_api_call()
        try:
            send_via_api(
                self.org_id,
                self.modal_proxy_url,
                "submit-reward",
                {
                    "roundNumber": round_num,
                    "stageNumber": stage_num,
                    "reward": reward,
                    "peerId": peer_id,
                },
            )
        except requests.exceptions.HTTPError as e:
            raise

    def submit_winners(self, round_num, winners, peer_id):
        verify_device_before_api_call()
        try:
            send_via_api(
                self.org_id,
                self.modal_proxy_url,
                "submit-winner",
                {"roundNumber": round_num, "winners": winners, "peerId": peer_id},
            )
        except requests.exceptions.HTTPError as e:
            raise


class PRGCoordinator:
    """
    Coordinator for the PRG game. We don't need contract address or ABI because we rely on the modal proxy app
    to handle routing requests to the correct backend via the endpoints.
    """

    # TODO: We might want to change the name of these arguments to match what's in the contract for clarity ("clueId" -> "roundIdx")
    def __init__(
        self,
        org_id: str,
        modal_proxy_url: str,
    ) -> None:
        self.org_id = org_id
        self.modal_proxy_url = modal_proxy_url

    def bet_token_balance(
        self, peer_id: str
    ) -> int:
        verify_device_before_api_call()
        try:
            response = send_via_api(
                self.org_id,
                self.modal_proxy_url,
                "bet-token-balance",
                {
                    "peerId": peer_id,
                },
            )
            if isinstance(response, dict) and "result" in response:
                # The new format returns the actual balance value
                return int(response["result"])
            else:
                get_logger().debug(f"Unexpected response format: {response}")
                return 0
        except requests.exceptions.HTTPError as e:
            if e.response is None or e.response.status_code != 500:
                raise

            get_logger().debug("Unknown error calling bet-token-balance endpoint! Continuing.")
            return 0

    def guess_answer(
        self, game_id: int, peer_id: str, clue_id: int, choice_idx: int, bet: int
    ) -> None:
        verify_device_before_api_call()
        try:
            send_via_api(
                self.org_id,
                self.modal_proxy_url,
                "guess-answer",
                {
                    "gameId": game_id,
                    "peerId": peer_id,
                    "clueId": clue_id,
                    "choiceIdx": choice_idx,
                    "bet": bet,
                },
            )
        except requests.exceptions.HTTPError as e:
            raise

    def claim_reward(
        self, game_id: int, peer_id: str
    ) -> None:
        verify_device_before_api_call()
        try:
            send_via_api(
                self.org_id,
                self.modal_proxy_url,
                "claim-reward",
                {"gameId": game_id, "peerId": peer_id},
            )
        except requests.exceptions.HTTPError as e:
            raise
