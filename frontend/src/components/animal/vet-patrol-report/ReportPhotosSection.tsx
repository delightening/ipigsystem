// 整體環境照（report-level 照片）（R82-7 由 VetPatrolReportDialog.tsx 抽出）

import { Trash2, ImagePlus } from 'lucide-react'
import { CaptionInput } from './CaptionInput'
import type { VetPatrolReportVM } from './useVetPatrolReport'

export function ReportPhotosSection({ vm }: { vm: VetPatrolReportVM }) {
    return (
        <div className="mt-4 pt-3 border-t">
            <div className="flex items-center justify-between mb-2">
                <span className="text-sm font-semibold">整體環境照（選填）</span>
                {vm.savedReportId ? (
                    <label className="flex items-center gap-1 text-xs text-status-success-solid hover:text-status-success-text cursor-pointer">
                        <ImagePlus className="h-3.5 w-3.5" />
                        上傳照片
                        <input
                            type="file"
                            accept="image/*"
                            capture="environment"
                            multiple
                            className="hidden"
                            onChange={vm.handleSelectReportPhoto}
                            disabled={vm.uploadReportPhotoMutation.isPending}
                        />
                    </label>
                ) : (
                    <span className="text-xs text-muted-foreground">草稿建立中...</span>
                )}
            </div>
            {vm.photos.length > 0 && (
                <div className="grid grid-cols-2 gap-3">
                    {vm.photos.map((photo) => (
                        <div key={photo.id} className="border rounded p-2 space-y-2">
                            <img
                                src={`/api/v1/vet-patrol-photos/${photo.id}/download`}
                                alt={photo.caption || photo.file_name}
                                className="w-full h-32 object-cover rounded bg-muted"
                            />
                            <CaptionInput
                                value={photo.caption}
                                placeholder="輸入解說（選填）"
                                className="text-xs"
                                onSave={(caption) => vm.updateReportCaptionMutation.mutate({
                                    photoId: photo.id,
                                    caption,
                                })}
                            />
                            <button
                                type="button"
                                onClick={() => vm.deleteReportPhotoMutation.mutate(photo.id)}
                                className="flex items-center gap-1 text-xs text-muted-foreground hover:text-destructive transition-colors"
                            >
                                <Trash2 className="h-3 w-3" /> 刪除
                            </button>
                        </div>
                    ))}
                </div>
            )}
        </div>
    )
}
