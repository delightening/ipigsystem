import React from 'react'

import { AnimalStatus } from '@/lib/api'
import { Button } from '@/components/ui/button'
import { GuestHide } from '@/components/ui/guest-hide'
import { Can } from '@/components/auth'
import { PERMISSIONS } from '@/lib/permissions.generated'
import { AlertTriangle, AlertOctagon, Zap } from 'lucide-react'

interface AnimalDetailActionsProps {
  status: AnimalStatus
  onEmergencyMedication: () => void
  onEuthanasiaOrder: () => void
  onSuddenDeath: () => void
}

export function AnimalDetailActions({
  status,
  onEmergencyMedication,
  onEuthanasiaOrder,
  onSuddenDeath,
}: AnimalDetailActionsProps) {
  if (status !== 'in_experiment' && status !== 'completed') return null

  return (
    <GuestHide>
      <div className="flex gap-2">
        {status === 'in_experiment' && (
          <>
            {/* \u7DCA\u6025\u7D66\u85E5\u7368\u7ACB\u65BC\u4E00\u822C record \u6B0A\u9650\uFF08\u5F8C\u7AEF observation.rs:105 \u5728 is_emergency \u6642
                \u53E6\u5916\u8981\u6C42 animal.record.emergency\uFF09\uFF0C\u6545\u9019\u88E1\u4E5F\u7528\u8A72\u78BC\u800C\u975E record.create\u3002 */}
            <Can permission={PERMISSIONS.ANIMAL_RECORD_EMERGENCY}>
              <Button
                variant="outline"
                className="border-status-warning-border text-status-warning-text hover:bg-status-warning-bg"
                onClick={onEmergencyMedication}
              >
                <AlertTriangle className="h-4 w-4 mr-2" />
                {'\u7DCA\u6025\u7D66\u85E5'}
              </Button>
            </Can>
            {/* \u26A0\uFE0F \u5F8C\u7AEF euthanasia.rs:41 \u6AA2\u7684\u662F `animal.euthanasia.create`\u2014\u2014\u90A3\u500B\u78BC
                **\u4E0D\u5728 permissions seed \u88E1**\uFF08startup/permissions.rs \u53EA\u6709 recommend /
                approve / execute / arbitrate\uFF09\uFF0Chas_permission \u6C38\u9060 false\uFF0C\u5BE6\u969B\u7B49\u540C
                \u300C\u53EA\u6709 ROLE_VET \u80FD\u958B\u55AE\u300D\u3002\u524D\u7AEF\u4E0D\u8DDF\u8457\u6284\u4E00\u500B\u4E0D\u5B58\u5728\u7684\u78BC\uFF0C\u4E5F\u4E0D\u6539\u7528 role \u786C\u5224\uFF0C
                \u6539\u7528 VET \u5BE6\u969B\u6301\u6709\u3001\u8A9E\u610F\u6700\u63A5\u8FD1\u7684 animal.euthanasia.recommend
                \uFF08seed \u88E1 VET \u6709\u6B64\u78BC\uFF09\u3002\u5F8C\u7AEF\u90A3\u500B\u6B7B\u78BC\u5217\u70BA PR 5\u300C\u53BB role \u786C\u5224\u300D\u7684\u9805\u76EE\u3002 */}
            <Can permission={PERMISSIONS.ANIMAL_EUTHANASIA_RECOMMEND}>
              <Button
                variant="outline"
                className="border-destructive text-destructive hover:bg-status-error-bg"
                onClick={onEuthanasiaOrder}
              >
                <AlertOctagon className="h-4 w-4 mr-2" />
                {'\u958B\u7ACB\u5B89\u6A02\u6B7B\u55AE'}
              </Button>
            </Can>
          </>
        )}
        {/* \u767B\u8A18\u731D\u6B7B\u8D70 sudden_death.rs:36 \u7684 animal.record.create */}
        <Can permission={PERMISSIONS.ANIMAL_RECORD_CREATE}>
          <Button
            variant="outline"
            className="border-destructive text-destructive hover:bg-status-error-bg"
            onClick={onSuddenDeath}
          >
            <Zap className="h-4 w-4 mr-2" />
            {'\u767B\u8A18\u731D\u6B7B'}
          </Button>
        </Can>
      </div>
    </GuestHide>
  )
}
