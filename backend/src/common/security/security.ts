// Author: Nguyễn Phồn Hiếu_HE191632 | Date: 9/11/2026
import {
  CanActivate, ExecutionContext, ForbiddenException, Injectable, SetMetadata, UnauthorizedException, createParamDecorator,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { RoleCode } from '../../model/entities';

/** Identity carried in the JWT and attached to every authenticated request. */
export interface AuthUser {
  userId: number;
  fullName: string;
  role: RoleCode;
  staffId: number | null;
  branchId: number | null;
  customerId: number | null;
}

export const ROLES_KEY = 'roles';
/** Restrict an endpoint to the given roles (BR4). SYS_ADMIN always passes. */
export const Roles = (...roles: RoleCode[]) => SetMetadata(ROLES_KEY, roles);

export const CurrentUser = createParamDecorator((_: unknown, ctx: ExecutionContext): AuthUser => {
  return ctx.switchToHttp().getRequest().user;
});

@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(private readonly jwt: JwtService) {}

  canActivate(ctx: ExecutionContext): boolean {
    const req = ctx.switchToHttp().getRequest();
    const header: string | undefined = req.headers['authorization'];
    if (!header?.startsWith('Bearer ')) throw new UnauthorizedException('Bạn chưa đăng nhập');
    try {
      req.user = this.jwt.verify<AuthUser>(header.slice(7));
      return true;
    } catch {
      throw new UnauthorizedException('Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại');
    }
  }
}

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(ctx: ExecutionContext): boolean {
    const roles = this.reflector.getAllAndOverride<RoleCode[]>(ROLES_KEY, [ctx.getHandler(), ctx.getClass()]);
    if (!roles?.length) return true;
    const user: AuthUser = ctx.switchToHttp().getRequest().user;
    if (user.role === 'SYS_ADMIN' || roles.includes(user.role)) return true;
    throw new ForbiddenException('Vai trò của bạn không được phép thực hiện chức năng này');
  }
}

/** Branch data scope (BR48): staff may only touch records of their own branch. */
export function assertSameBranch(user: AuthUser, branchId: number): void {
  if (user.role === 'SYS_ADMIN') return;
  if (user.branchId !== branchId) {
    throw new ForbiddenException('Dữ liệu thuộc chi nhánh khác, bạn không có quyền truy cập');
  }
}
