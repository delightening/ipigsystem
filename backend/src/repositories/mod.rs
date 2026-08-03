// Repository 層：封裝重複使用的 SQL 查詢（≥2 處出現）
// 依賴方向：Services → Repositories → Models

pub mod ai;
pub mod equipment;

pub use ai::AiRepository;
pub mod accounting;
pub mod application_notice;
pub mod audit_log;
pub mod data_retention;
pub mod glp_compliance;
pub mod hr;
pub mod notification;
pub mod pen;
pub mod product;
pub mod qa_plan;
pub mod role;
pub mod sku;
pub mod user;
pub mod user_preference;
pub mod warehouse;
