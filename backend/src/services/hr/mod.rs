// HR 服務模組
// 拆分自原始 hr.rs（1,453 行）

mod attendance;
pub mod balance;
mod dashboard;
mod leave;
pub mod overtime;

pub use leave::CancelLeaveOutcome;

pub struct HrService;
