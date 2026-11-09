import { Injectable } from '@nestjs/common';
import { EntityManager } from 'typeorm';
import { AuditLog, Notification } from '../../model/entities';

/** In-app notifications (INotifier) and audit trail (BR50) written inside the caller's transaction. */
@Injectable()
export class NotificationService {
  async notify(m: EntityManager, userIds: number[], title: string, content: string, referenceType: string, referenceId: number) {
    const repo = m.getRepository(Notification);
    for (const userId of [...new Set(userIds)].filter(Boolean)) {
      await repo.insert({ userId, channel: 'IN_APP', title, content, referenceType, referenceId, status: 'SENT', sentAt: new Date() });
    }
  }

  async audit(m: EntityManager, userId: number, action: string, entityName: string, entityId: number, newValue?: object) {
    await m.getRepository(AuditLog).insert({ userId, action, entityName, entityId, newValue: newValue ?? null });
  }
}
