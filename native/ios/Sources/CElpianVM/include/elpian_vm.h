/*
 * elpian_vm.h — the C ABI of libelpian_vm (rust/crates/elpian-ffi).
 *
 * Every `char *` returned is owned by the caller and released with
 * elpian_free_string(), exactly once. String arguments are NUL-terminated
 * UTF-8 (NULL reads as ""). Execution calls answer
 * {"hasHostCall":bool,"hostCallData":string,"resultValue":string};
 * governance calls answer JSON, failures in band as {"error":"..."}.
 */
#ifndef ELPIAN_VM_H
#define ELPIAN_VM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

const char *elpian_last_error(void);
void elpian_free_string(char *ptr);
void elpian_init(void);

int32_t elpian_create_vm_from_ast(const char *id, const char *ast);
int32_t elpian_create_vm_from_code(const char *id, const char *code);
int32_t elpian_create_vm_from_bytecode(const char *id, const uint8_t *bytes, size_t length);
int32_t elpian_validate_ast(const char *ast);
char *elpian_execute(const char *id);
char *elpian_execute_func(const char *id, const char *name, int64_t callback_id);
char *elpian_execute_func_with_input(const char *id, const char *name, const char *input, int64_t callback_id);
char *elpian_continue_execution(const char *id, const char *input);
char *elpian_deliver_host_message(const char *id, const char *message, int64_t callback_id);
int32_t elpian_destroy_vm(const char *id);
int32_t elpian_vm_exists(const char *id);

/* Governance. */
char *elpian_limits(const char *id);
char *elpian_usage(const char *id);
char *elpian_subtree_usage(const char *id);
char *elpian_local_capabilities(const char *id);
char *elpian_effective_capabilities(const char *id);
char *elpian_state(const char *id);
char *elpian_pause(const char *id);
char *elpian_resume(const char *id);
char *elpian_terminate(const char *id);
char *elpian_tree(const char *id);
char *elpian_terminate_tree(const char *id);
char *elpian_pause_tree(const char *id);
char *elpian_destroy_tree(const char *id);
char *elpian_snapshot(const char *id);
char *elpian_set_limits(const char *id, const char *limits_json);
char *elpian_set_capability(const char *id, const char *capability, int32_t allowed);
char *elpian_set_capabilities(const char *id, const char *caps_json);
char *elpian_sandbox_capabilities(const char *id, const char *granted_json);
char *elpian_capability_allows(const char *id, const char *api_name);
char *elpian_charge_storage(const char *id, int64_t delta);
char *elpian_adopt(const char *parent_id, const char *child_id);
char *elpian_enforce_tree_budgets(void);

/* Any export above by name, arguments as a JSON array; NULL for an unknown name.
 * Integer-returning exports answer "true"/"false". */
char *elpian_call_json(const char *symbol, const char *args_json);

#ifdef __cplusplus
}
#endif

#endif /* ELPIAN_VM_H */
