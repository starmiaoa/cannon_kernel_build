#include <linux/kernel.h>
#include <linux/list.h>

struct devapc_vio_callbacks;

#ifndef CONFIG_MTK_DEVAPC
/*
 * No-op shim: the real registration lives in the devapc driver, which is
 * disabled here because the 2021 code BUGs on 2023 TINYSYS violations.
 * clkdbg/cmdq/eccci call register_devapc_vio_callback unguarded, so keep
 * the symbol linkable with a no-op registration.
 */
void register_devapc_vio_callback(struct devapc_vio_callbacks *viocb)
{
	INIT_LIST_HEAD(&viocb->list);
}
#endif
