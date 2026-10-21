from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.response import Response

from .models import Device, Notification
from .serializers import DeviceSerializer, NotificationSerializer


class DeviceDetailView(generics.GenericAPIView):
    serializer_class = DeviceSerializer

    def put(self, request, device_id):
        device = Device.objects.filter(user=request.user, device_id=device_id).first()
        serializer = self.get_serializer(device, data={**request.data, "device_id": device_id})
        serializer.is_valid(raise_exception=True)
        if device is None:
            device = serializer.save(user=request.user, last_seen_at=timezone.now())
            response_status = status.HTTP_201_CREATED
        else:
            device = serializer.save(last_seen_at=timezone.now())
            response_status = status.HTTP_200_OK
        return Response(DeviceSerializer(device).data, status=response_status)

    def delete(self, request, device_id):
        device = get_object_or_404(Device, user=request.user, device_id=device_id)
        device.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class NotificationListView(generics.ListAPIView):
    serializer_class = NotificationSerializer

    def get_queryset(self):
        return Notification.objects.filter(user=self.request.user)


class NotificationOpenedView(generics.GenericAPIView):
    def post(self, request, pk):
        notification = get_object_or_404(Notification, user=request.user, pk=pk)
        if notification.opened_at is None:
            notification.opened_at = timezone.now()
            notification.status = Notification.Status.OPENED
            notification.save(update_fields=("opened_at", "status", "updated_at"))
        return Response(NotificationSerializer(notification).data)
