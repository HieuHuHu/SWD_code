// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
import { ArgumentsHost, Catch, ExceptionFilter } from '@nestjs/common';
import { QueryFailedError } from 'typeorm';

/** Maps database constraint violations (e.g. two users registering the same email at once) to clean HTTP errors. */
@Catch(QueryFailedError)
export class DbExceptionFilter implements ExceptionFilter {
  catch(err: QueryFailedError & { code?: string; constraint?: string }, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse();
    const map: Record<string, [number, string]> = {
      '23505': [409, 'Dữ liệu đã tồn tại (trùng thông tin duy nhất)'],
      '23514': [409, 'Dữ liệu vi phạm ràng buộc nghiệp vụ'],
      '23503': [400, 'Dữ liệu tham chiếu không tồn tại'],
    };
    const [status, message] = map[err.code ?? ''] ?? [500, 'Lỗi cơ sở dữ liệu'];
    if (status === 500) console.error(err);
    res.status(status).json({ statusCode: status, message, constraint: err.constraint });
  }
}
