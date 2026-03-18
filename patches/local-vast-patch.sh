#!/bin/sh
# Local patch for X1-VAST behind HTTPS reverse proxy.
# The dongle only handles 1 request at a time, so we skip full discovery
# and target X1HybridGen4 directly.
#
# Usage: curl -s https://raw.githubusercontent.com/Jhacarreiro/solax/master/patches/local-vast-patch.sh | sh

CONTAINER=homeassistant
PKG=/usr/local/lib/python3.14/site-packages/solax

echo "=== Patching __init__.py (skip full discovery) ==="
docker exec $CONTAINER sh -c "cat > $PKG/__init__.py << 'PYEOF'
\"\"\"Support for Solax inverter via local API.\"\"\"
import asyncio
import logging
from solax.discovery import discover
from solax.inverter import Inverter, InverterResponse
from solax.inverter_http_client import REQUEST_TIMEOUT
from solax.inverters.x1_hybrid_gen4 import X1HybridGen4
_LOGGER = logging.getLogger(__name__)
__all__ = (
    \"discover\",
    \"real_time_api\",
    \"rt_request\",
    \"Inverter\",
    \"InverterResponse\",
    \"RealTimeAPI\",
    \"REQUEST_TIMEOUT\",
)
async def rt_request(inv: Inverter, retry, t_wait=0) -> InverterResponse:
    if t_wait > 0:
        msg = \"Timeout connecting to Solax inverter, waiting %d to retry.\"
        _LOGGER.error(msg, t_wait)
        await asyncio.sleep(t_wait)
    new_wait = (t_wait * 2) + 5
    retry = retry - 1
    try:
        return await inv.get_data()
    except asyncio.TimeoutError:
        if retry > 0:
            return await rt_request(inv, retry, new_wait)
        _LOGGER.error(\"Too many timeouts connecting to Solax.\")
        raise
async def real_time_api(ip_address, port=80, pwd=\"\"):
    i = await discover(
        ip_address, port, pwd,
        inverters=[X1HybridGen4],
        return_when=asyncio.ALL_COMPLETED,
    )
    return RealTimeAPI(i)
class RealTimeAPI:
    def __init__(self, inv: Inverter):
        self.inverter = inv
    async def get_data(self) -> InverterResponse:
        return await rt_request(self.inverter, 3)
PYEOF"

echo "=== Restarting $CONTAINER ==="
docker restart $CONTAINER
echo "=== Done. Wait 2 min then add SolaX Power in HA UI. ==="
