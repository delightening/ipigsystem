use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Extension, Json,
};
use uuid::Uuid;
use validator::Validate;

use crate::{
    middleware::{ActorContext, CurrentUser},
    models::{
        Animal, CreatePlannedExperimentRequest, PlannedExperiment, PlannedExperimentResponse,
        ReservableAnimalRow, ReservableQuery, ReservationPlanningGroup, ReserveAnimalsRequest,
        UnreserveAnimalsRequest, UpdatePlannedExperimentRequest, UpdateRemarkRequest,
    },
    require_permission,
    services::{AnimalService, PlannedExperimentService},
    AppState, Result,
};

/// 動物預約與試驗規劃：執行秘書（IACUC_STAFF，持 `animal.info.assign`）+ admin（自動 bypass）管理。
const PERM: &str = "animal.info.assign";

pub async fn list_planned_experiments(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
) -> Result<Json<Vec<PlannedExperimentResponse>>> {
    require_permission!(current_user, PERM);
    Ok(Json(PlannedExperimentService::list(&state.db).await?))
}

pub async fn get_planned_experiment(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Path(id): Path<Uuid>,
) -> Result<Json<PlannedExperiment>> {
    require_permission!(current_user, PERM);
    Ok(Json(PlannedExperimentService::get(&state.db, id).await?))
}

pub async fn create_planned_experiment(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Json(req): Json<CreatePlannedExperimentRequest>,
) -> Result<(StatusCode, Json<PlannedExperiment>)> {
    require_permission!(current_user, PERM);
    req.validate()?;
    let actor = ActorContext::User(current_user);
    let v = PlannedExperimentService::create(&state.db, &actor, &req).await?;
    Ok((StatusCode::CREATED, Json(v)))
}

pub async fn update_planned_experiment(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdatePlannedExperimentRequest>,
) -> Result<Json<PlannedExperiment>> {
    require_permission!(current_user, PERM);
    req.validate()?;
    let actor = ActorContext::User(current_user);
    let v = PlannedExperimentService::update(&state.db, &actor, id, &req).await?;
    Ok(Json(v))
}

pub async fn delete_planned_experiment(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Path(id): Path<Uuid>,
) -> Result<StatusCode> {
    require_permission!(current_user, PERM);
    let actor = ActorContext::User(current_user);
    PlannedExperimentService::delete(&state.db, &actor, id).await?;
    Ok(StatusCode::NO_CONTENT)
}

/// 批次預約動物到試驗（Phase 2）。回實際被預約的動物。
pub async fn reserve_animals(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Json(req): Json<ReserveAnimalsRequest>,
) -> Result<Json<Vec<Animal>>> {
    require_permission!(current_user, PERM);
    req.validate()?;
    let actor = ActorContext::User(current_user);
    Ok(Json(
        PlannedExperimentService::reserve(&state.db, &actor, &req).await?,
    ))
}

/// 批次解除預約（Phase 2）。
pub async fn unreserve_animals(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Json(req): Json<UnreserveAnimalsRequest>,
) -> Result<Json<Vec<Animal>>> {
    require_permission!(current_user, PERM);
    req.validate()?;
    let actor = ActorContext::User(current_user);
    Ok(Json(
        PlannedExperimentService::unreserve(&state.db, &actor, &req).await?,
    ))
}

/// 搜尋可預約動物（未分配未預約，體重/月齡/性別篩選，Phase 2）。
pub async fn list_reservable_animals(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Query(query): Query<ReservableQuery>,
) -> Result<Json<Vec<ReservableAnimalRow>>> {
    require_permission!(current_user, PERM);
    Ok(Json(
        PlannedExperimentService::search_reservable(&state.db, &query).await?,
    ))
}

/// 更新動物備註（Phase 5）：規劃頁整格 inline 編輯。權限沿用規劃頁 `animal.info.assign`
/// （秘書 / admin 在此管理全場活豬備註）。audit 走 `ANIMAL_REMARK_UPDATE`。
pub async fn update_animal_remark(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Path(id): Path<Uuid>,
    Json(req): Json<UpdateRemarkRequest>,
) -> Result<Json<Animal>> {
    require_permission!(current_user, PERM);
    req.validate()?;
    let actor = ActorContext::User(current_user);
    Ok(Json(
        AnimalService::update_remark(&state.db, &actor, id, req.remark).await?,
    ))
}

/// 規劃分組查詢（Phase 3）：全場動物按試驗分組 + 需求/已預約/已分配/缺口。
pub async fn get_reservation_planning(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
) -> Result<Json<Vec<ReservationPlanningGroup>>> {
    require_permission!(current_user, PERM);
    Ok(Json(
        PlannedExperimentService::get_reservation_planning(&state.db).await?,
    ))
}
