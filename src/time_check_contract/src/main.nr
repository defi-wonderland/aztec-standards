// TODO: uncomment when timestamp based tests are implemented
// mod test;

use dep::aztec::macros::aztec;

#[aztec]
// Timestamp validation in private circuits, for secure and anonymous time-based logic execution.
contract TimeCheck {

    /** ==========================================================
     * ========================= IMPORTS =========================
     * ======================================================== */

    use dep::aztec::macros::functions::{internal, private, public};

    /** ==========================================================
     * ==================== PRIVATE ENTRYPOINTS ==================
     * ======================================================== */

    #[private]
    fn timestamp_gt(t: u64) {
        TimeCheck::at(context.this_address()).assert_timestamp_gt(t).enqueue(&mut context);
    }

    #[private]
    fn timestamp_lt(t: u64) {
        TimeCheck::at(context.this_address()).assert_timestamp_lt(t).enqueue(&mut context);
    }

    /** ==========================================================
     * ===================== PUBLIC ENTRYPOINTS ==================
     * ======================================================== */

    #[public]
    #[internal] // TODO: is internal needed here?
    fn assert_timestamp_gt(t: u64) {
        let current_t = context.timestamp();
        // TODO: define if = should pass or not
        assert(current_t >= t, "Timestamp not greater than current");
    }

    #[public]
    #[internal] // TODO: is internal needed here?
    fn assert_timestamp_lt(t: u64) {
        let current_t = context.timestamp();
        // TODO: define if = should pass or not
        assert(current_t <= t, "Timestamp not lesser than current");
    }

    // NOTE: assert_timestamp_eq has no actual application (prone to fail)
    /* TODO:
     * Implement:
     * - timestamp_gt_by_delta(t:64, delta: 64)
     * - timestamp_lt_by_delta(t:64, delta: 64)
     */
}

